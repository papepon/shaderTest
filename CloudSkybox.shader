Shader "Custom/URP/CloudSkybox"
{
    Properties
    {
        [Header(Sky Gradient)]
        _SkyColorTop     ("Sky Color (Top)", Color) = (0.25, 0.5, 0.9, 1)
        _SkyColorHorizon ("Sky Color (Horizon)", Color) = (0.75, 0.85, 0.95, 1)
        _HorizonExponent ("Horizon Blend Sharpness", Range(0.1, 8)) = 2

        [Header(Cloud Texture)]
        _CloudTex          ("Cloud Texture (RGB=Color, A=Coverage)", 2D) = "black" {}
        _CloudColor        ("Cloud Tint", Color) = (1,1,1,1)
        _CloudOpacity      ("Cloud Opacity", Range(0,1)) = 1
        _CloudScrollSpeed  ("Cloud Scroll Speed (X,Y)", Vector) = (0.005, 0.0, 0, 0)
        _CloudTiling       ("Cloud UV Tiling (X,Y)", Vector) = (1, 1, 0, 0)
        _CloudHeightFalloff("Cloud Height Falloff (horizon側を薄く)", Range(0,1)) = 0.25

        [Header(Exposure)]
        _Exposure ("Exposure", Range(0,4)) = 1
    }

    SubShader
    {
        Tags { "Queue"="Background" "RenderType"="Background" "PreviewType"="Skybox" "RenderPipeline"="UniversalPipeline" }
        Cull Off
        ZWrite Off
        ZTest LEqual

        Pass
        {
            Name "SkyboxCloudForward"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 3.0

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float3 viewDir     : TEXCOORD0;
            };

            TEXTURE2D(_CloudTex);
            SAMPLER(sampler_CloudTex);

            CBUFFER_START(UnityPerMaterial)
                half4 _SkyColorTop;
                half4 _SkyColorHorizon;
                half  _HorizonExponent;
                half4 _CloudColor;
                half  _CloudOpacity;
                half4 _CloudScrollSpeed;
                half4 _CloudTiling;
                half  _CloudHeightFalloff;
                half  _Exposure;
            CBUFFER_END

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                // Skyboxのメッシュは原点中心の立方体/球なので、頂点位置=視線方向として使える
                OUT.viewDir = IN.positionOS.xyz;
                OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz);
                return OUT;
            }

            // 方向ベクトル -> 正距円筒(パノラマ)UV
            float2 DirToPanoramicUV(float3 dir)
            {
                float2 uv;
                uv.x = atan2(dir.x, -dir.z) / (2.0 * PI) + 0.5;
                uv.y = asin(clamp(dir.y, -1.0, 1.0)) / PI + 0.5;
                return uv;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                float3 dir = normalize(IN.viewDir);

                // --- 空のグラデーション ---
                half t = saturate(dir.y * 0.5 + 0.5);
                t = pow(t, _HorizonExponent);
                half3 skyColor = lerp(_SkyColorHorizon.rgb, _SkyColorTop.rgb, t);

                // --- 雲テクスチャ ---
                float2 uv = DirToPanoramicUV(dir) * _CloudTiling.xy;
                uv += _CloudScrollSpeed.xy * _Time.y;
                half4 cloudSample = SAMPLE_TEXTURE2D(_CloudTex, sampler_CloudTex, uv);

                half cloudMask = cloudSample.a * _CloudOpacity;
                // 地平線・下方向は雲を薄くフェード
                half heightFade = saturate(dir.y + _CloudHeightFalloff);
                cloudMask *= heightFade;

                half3 cloudColor = cloudSample.rgb * _CloudColor.rgb;
                half3 finalColor = lerp(skyColor, cloudColor, cloudMask);

                finalColor *= _Exposure;
                return half4(finalColor, 1.0);
            }
            ENDHLSL
        }
    }
    FallBack Off
}
