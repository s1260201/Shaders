Shader "Custom/RayMarchingStep1"
{
	Properties
	{
		_Radius("Radius", Range(0.0,1.0)) = 1.0
		_XLight("Light-X", Float) = 0.0
		_YLight("Light-Y", Float) = 0.0
		_ZLight("Light-Z", Float) = 0.0
	}
	SubShader
	{
                //衝突しないピクセルは透明
		Tags{ "Queue" = "Transparent" "LightMode"="ForwardBase"}
		LOD 100

		Pass
		{
			ZWrite On
                        //アルファ値が機能するために必要
			Blend SrcAlpha OneMinusSrcAlpha

			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag

			#include "UnityCG.cginc"

			struct appdata
			{
				float4 vertex : POSITION;
				float2 uv : TEXCOORD0;
			};

			struct v2f
			{
				float2 uv : TEXCOORD0;
				float4 pos : POSITION1;
				float4 vertex : SV_POSITION;
			};

			v2f vert(appdata v)
			{
				v2f o;
				o.vertex = UnityObjectToClipPos(v.vertex);
                                //ローカル→ワールド座標に変換
				o.pos = mul(unity_ObjectToWorld, v.vertex);
				o.uv = v.uv;
				return o;
			}

			float _Radius;
			float _XLight;
			float _YLight;
			float _ZLight;
			float3 _SkyBottomColor;

			
			float sphere(float3 pos)
            {
                return length(pos) - _Radius;
            }

			float mod(float x, float y)
            {
                return x - y * floor(x / y);
            }

            float2 mod(float2 x, float2 y)
            {
                return x - y * floor(x / y);
            }

			float2 opRep(float2 p, float2 interval)
            {
                return mod(p, interval) - interval * 0.5;
            }
            
            float dBalls(float3 p)
            {
                p.z = opRep(p.z, 4);
                return sphere(p - float3(0, 1, 0));
            }


			//円柱の距離関数
			float sdCappedCylinder(float3 p, float3 a, float3 b, float r) //(レイポジ, 下面座標, 上面座標, 太さ)  右手左手系に注意
			{
				float3  ba = b - a;
				float3  pa = p - a;
				float baba = dot(ba,ba);
				float paba = dot(pa,ba);
				float x = length(pa*baba-ba*paba) - r*baba;
				float y = abs(paba-baba*0.5)-baba*0.5;
				float x2 = x*x;
				float y2 = y*y*baba;
				float d = (max(x,y)<0.0)?-min(x2,y2):(((x>0.0)?x2:0.0)+((y>0.0)?y2:0.0));
				return sign(d)*sqrt(abs(d))/baba;
			}

			//Boxの距離関数
			float sdBox( float3 p, float3 b )
			{
				float3 q = abs(p) - b;
				return length(max(q,0.0)) + min(max(q.x,max(q.y,q.z)),0.0);
			}

			float dTrii(float3 p, float3 a, float3 b, float r){
				p.z = opRep(p.z,4);
				return sdCappedCylinder(p,a,b,r);
			}

			float dBox(float3 p,float3 a){
				p.z = opRep(p.z,4);
				return sdBox(p,a);
			}

			// input obj info there
			float getSdf(float3 pos){
				float marchingDist = dTrii(pos,float3(0.75,0.0,0.0),float3(0.75,2.3,0.0) ,0.1);
				float marchingDist2 = dTrii(pos,float3(-0.75,0.0,0.0),float3(-0.75,2.3,0.0) ,0.1);
				float marchingDist3 = dBox(float3(pos.x,pos.y-2.3,pos.z),float3(1.2,0.1,0.2));
				float marchingDist4 = dBox(float3(pos.x,pos.y-1.8,pos.z),float3(0.7,0.1,0.2));

				return min(min(min(marchingDist,marchingDist2),marchingDist3),marchingDist4);
			}

			float calcSoftshadow(float3 ro, float3 rd, float mint, float tmax)
            {
                // bounding volume
                float tp = (0.8 - ro.y) / rd.y;
                if (tp > 0.0) tmax = min(tmax, tp);
                
                float res = 1.0;
                float t = mint;
                for (int i = 0; i < 24; i++)
                {
                    float h = getSdf(ro + rd * t).x;
                    float s = clamp(8.0 * h / t, 0.0, 1.0);
                    res = min(res, s * s * (3.0 - 2.0 * s));
                    t += clamp(h, 0.02, 0.2);
                    if (res < 0.004 || t > tmax) break;
                }
                return clamp(res, 0.0, 1.0);
            }

			float4 rayMarch(float3 pos, float3 rayDir, int StepNum){
				float3 light = float3(_XLight,_YLight,_ZLight);
				int fase = 0;
				float t = 0;
				float d = getSdf(pos);
				float3 col = float3(0.549,0.431,0.282);

				while(fase < StepNum && abs(d) > 0.001){
					t += d;
					pos += rayDir * d;
					d = getSdf(pos);
					fase++;
				}
				float shadow = calcSoftshadow(pos, light, 0.25, 5);
				float invFog = exp(-0.15 * t);
				col *= shadow;
                col = lerp(_SkyBottomColor, col, invFog);
				if(step(StepNum,fase)){
					return float4(0,0,0,1);
				}else{
					return float4(col,1);
				}
				
			}

			fixed4 frag(v2f i) : SV_Target
			{
				float3 col = float3(0,0,0);
				// レイの初期位置(ピクセルのワールド座標)
				float3 pos = i.pos.xyz;
				// レイの進行方向
				float3 rayDir = normalize(pos.xyz - _WorldSpaceCameraPos);

				int StepNum = 30;
				float t = 0;
				return rayMarch(pos,rayDir,StepNum);

			}
			ENDCG
		}
	}
}