Shader "PivotPainter2/URP_Simple"
{
    Properties
    {
        _BaseMap ("Base Map", 2D) = "white" {}
        _BaseColor ("Base Color", Color) = (1,1,1,1)

        _MetricScale("Metric Scale", float) = 0.01
        _posAndIndexTex("Pivot+Index", 2D) = "white" {}
        _xVectorAndExtentTex("Axis+Extent", 2D) = "white" {}

        _RotationSpeed("Rotation Speed", float) = 1
        //////////////////////////////////////////////////////
        _WindDirection("Wind Direction", Vector) = (1,0,0,0)
        _WindStrength("Wind Strength", Float) = 0.3
        _WindFrequency("Wind Frequency", Float) = 1.5

    }

    SubShader
    {
        Tags
        {
            "RenderPipeline"="UniversalPipeline"
        }

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            // URP Core
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"



            // -------------------------------------
            // Properties
            // -------------------------------------
            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            float4 _BaseColor;

            float _MetricScale;
            float _RotationSpeed;

            TEXTURE2D(_posAndIndexTex);
            SAMPLER(sampler_posAndIndexTex);

            TEXTURE2D(_xVectorAndExtentTex);
            SAMPLER(sampler_xVectorAndExtentTex);

            float4 _WindDirection;
            float _WindStrength;
            float _WindFrequency;



                        // PivotPainter2
            #include "PivotPainter2.cginc"
            //頂点回転用
            float3 RotateAboutAxis(float4 NormalizedRotationAxisAndAngle, float3 PositionOnAxis, float3 Position)
            {
                float3 ClosestPointOnAxis = PositionOnAxis + NormalizedRotationAxisAndAngle.xyz * dot(NormalizedRotationAxisAndAngle.xyz, Position - PositionOnAxis);
                float3 UAxis = Position - ClosestPointOnAxis;
                float3 VAxis = cross(NormalizedRotationAxisAndAngle.xyz, UAxis);
                float CosAngle;
                float SinAngle;
                sincos(NormalizedRotationAxisAndAngle.w, SinAngle, CosAngle);
                float3 R = UAxis * CosAngle + VAxis * SinAngle;
                float3 RotatedPosition = ClosestPointOnAxis + R;
                return RotatedPosition - Position;
            }

            /////////////Vector回転用
            float3 RotateVector(float4 axisAngle, float3 vec)
            {
                float3 U = vec;
                float3 V = cross(axisAngle.xyz, U);

                float s, c;
                sincos(axisAngle.w, s, c);

                return U * c + V * s;
            }

            ////////////

            float ComputeWindAngle(float3 worldPos, float extent, float time)
            {
                // 風方向に沿った位置で位相を変える
                float windPhase = dot(worldPos, normalize(_WindDirection.xyz)) * 0.2;

                // 高さや extent で揺れの強さを変える（お好みで調整）
                float heightFactor = saturate(worldPos.y * 0.2);
                float extentFactor = saturate(extent);

                float base = sin(time * _WindFrequency + windPhase);

                // 全体の強さをまとめる
                float angle = base * _WindStrength * (0.3 + heightFactor + extentFactor);

                return angle; // ラジアンとして扱う
            }


            // -------------------------------------
            // Vertex Input / Output
            // -------------------------------------
            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float2 uv         : TEXCOORD0;
                float2 uv1        : TEXCOORD1;   // PivotPainter UV
                float4 tangentOS  : TANGENT;   // ← 必須！
                float4 color      : COLOR;     // PigHair の場合は階層情報など
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv          : TEXCOORD0;
                float3 tangentWS   : TEXCOORD1;
                float3 normalWS    : TEXCOORD2;
            };

            // -------------------------------------
            // Vertex Shader
            // -------------------------------------
            Varyings vert(Attributes IN)
            {
                Varyings OUT;

                // 1) PivotPainter の階層復元
                Hierachy h;
                RebuildHierachy(IN.uv1, _posAndIndexTex_TexelSize.zw, h);

                // 2) Pivot の座標
                //float3 pivotLocal = ConvertCoord(SamplePivotAndIndex(h.pivotUVs[0]).xyz);
                //float3 pivotWorld = mul(unity_ObjectToWorld, float4(pivotLocal, 1)).xyz;


                // 3) 軸ベクトル
                //float4 axisData = SampleXVectorAndExtent(h.extentUVs[0]);
                //float3 axis = DecodeAxisVector(axisData.rgb);
                /////////////////////////////
                //float extent = axisData.w;
                // 4) 回転角度
                //float angle = _Time.y * _RotationSpeed;

                // 5) 頂点のワールド座標
                float3 worldPos = mul(unity_ObjectToWorld, IN.positionOS).xyz;

                //////////////////////////////////

                // 時間（_Time.y など URP 共通のものを使用）
                float time = _Time.y;

                // 風による追加角度
                //float windAngle = ComputeWindAngle(worldPos, extent, time);

                // 合成角度
                //float totalAngle = angle + windAngle;

                // 回転用パラメータ
                //float4 axisAndAngle = float4(axis, totalAngle);

                //////////////////////////////////////////////////


                // 6) PivotPainter 回転
                //float3 offset = RotateAboutAxis(axisAndAngle, pivotWorld, worldPos);
                //worldPos += offset;


                //Normal回転用
                float3 normalWS = TransformObjectToWorldNormal(IN.normalOS);
                //normalWS = RotateAboutAxis(axisAndAngle, pivotWorld, normalWS);
                //normalWS =RotateVector(axisAndAngle, normalWS);

                //Tangent
                float3 tangentWS = TransformObjectToWorldDir(IN.tangentOS.xyz);
                //tangentWS = RotateAboutAxis(axisAndAngle, pivotWorld, tangentWS);
                //tangentWS = RotateVector(axisAndAngle, tangentWS);

                // 最大4レベル想定（PivotPainter2 標準）
                [unroll]
                for (int i = 0; i < 4; i++)
                {
                    // 無効レベルならスキップ（cginc 側でそういうフラグがあればそれを使う）
                    if (h.pivotUVs[i].x < 0) break;

                    // そのレベルの Pivot
                    float3 pivotLocal = ConvertCoord(SamplePivotAndIndex(h.pivotUVs[i]).xyz);
                    float3 pivotWorld = mul(unity_ObjectToWorld, float4(pivotLocal, 1)).xyz;

                    // そのレベルの Axis + Extent
                    float4 axisData = SampleXVectorAndExtent(h.extentUVs[i]);
                    float3 axis     = DecodeAxisVector(axisData.rgb);
                    float  extent   = axisData.w;

                    // ベースの回転角（全レベル共通の時間アニメーション）
                    float baseAngle = time * _RotationSpeed;

                    // 風の角度（レベルごとに少し変化させても良い）
                    float windAngle = ComputeWindAngle(worldPos, extent, time);

                    // 合成角度
                    float totalAngle = baseAngle + windAngle;

                    float4 axisAndAngle = float4(axis, totalAngle);

                    // 位置：差分回転
                    float3 offset = RotateAboutAxis(axisAndAngle, pivotWorld, worldPos);
                    worldPos += offset;

                    // ノーマル・接線：方向回転
                    normalWS  = RotateVector(axisAndAngle, normalWS);
                    tangentWS = RotateVector(axisAndAngle, tangentWS);
                }


                // 7) クリップ空間へ
                OUT.positionHCS = TransformWorldToHClip(worldPos);
                OUT.uv = IN.uv;

                //Normal, Tangent
                OUT.normalWS = normalWS;
                OUT.tangentWS = tangentWS;

                return OUT;
            }

            // -------------------------------------
            // Fragment Shader
            // -------------------------------------
            half4 frag(Varyings IN) : SV_Target
            {


                float3 normal = normalize(IN.normalWS);

                // URP のメインライトを取得
                Light mainLight = GetMainLight();

                // ライト方向（ワールド空間）
                float3 lightDir = normalize(mainLight.direction);

                // NdotL
                float NdotL = saturate(dot(normal, -lightDir));

                // 半ランバートで柔らかく
                float diffuse = NdotL * 0.5 + 0.5;

                float4 albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv) * _BaseColor;// ← あなたの Albedo に置き換え

                //return albedo; 

                return float4(albedo * diffuse * mainLight.color, 1);
            }

            ENDHLSL
        }
    }
}
