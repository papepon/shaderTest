Shader "Hidden/ProjectionFullscreen"
{
    Properties
    {
        _BlitTexture ("Source Texture", 2D) = "white" {}
        _ProjectorTex ("Projection Texture", 2D) = "white" {}
        _ProjectionStrength ("Projection Strength", Range(0,1)) = 1.0
    }

    SubShader
    {
        Tags
        {
            "RenderType"     = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
        }

        Pass
        {
            Name "ProjectionFullscreen"
            ZWrite Off
            ZTest  Always
            Blend SrcAlpha OneMinusSrcAlpha
            Cull   Off

            HLSLPROGRAM
            #pragma target   4.5
            #pragma vertex   Vert
            #pragma fragment Frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareNormalsTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                uint vertexID : SV_VertexID;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 texcoord   : TEXCOORD0;
            };

            Varyings Vert(Attributes input)
            {
                Varyings output;
                output.texcoord = float2(
                    (input.vertexID << 1) & 2,
                     input.vertexID       & 2
                );
                output.positionCS = float4(
                    output.texcoord * 2.0 - 1.0, 0.0, 1.0);
                #if UNITY_UV_STARTS_AT_TOP
                    output.texcoord.y = 1.0 - output.texcoord.y;
                #endif
                return output;
            }

            //TEXTURE2D(_BlitTexture);      SAMPLER(sampler_BlitTexture);
            TEXTURE2D(_CameraOpaqueTexture); SAMPLER(sampler_CameraOpaqueTexture);
            TEXTURE2D(_ProjectorTex);     SAMPLER(sampler_ProjectorTex);

            // URPのスクリーンスペースシャドウ
            //TEXTURE2D(_ScreenSpaceShadowmapTexture); SAMPLER(sampler_ScreenSpaceShadowmapTexture);

            CBUFFER_START(UnityPerMaterial)
                float4   _BlitTexture_ST;
                float4   _ProjectorTex_ST;
                float    _ProjectionStrength;
                float4x4 _ProjectorVP;
                float    _BorderFade;        // ✅ 追加 境界フェードの幅(0=なし 0.1=緩やか)
                float    _EdgeFadeThreshold; // ✅ 追加 輪郭フェードの閾値(0.01〜0.1)
            CBUFFER_END

            half4 Frag(Varyings input) : SV_Target
            {
                float2 uv = input.texcoord;

                //half4 baseColor = SAMPLE_TEXTURE2D(_BlitTexture, sampler_BlitTexture, uv);
                half4 baseColor = SAMPLE_TEXTURE2D(_CameraOpaqueTexture, sampler_CameraOpaqueTexture, uv);

                float rawDepth = SampleSceneDepth(uv);

                #if UNITY_REVERSED_Z
                    if (rawDepth <= 0.0001) return baseColor;
                #else
                    if (rawDepth >= 0.9999) return baseColor;
                #endif

                float3 worldPos = ComputeWorldSpacePosition(uv, rawDepth, UNITY_MATRIX_I_VP);

                float4 projClip = mul(_ProjectorVP, float4(worldPos, 1.0));
                if (projClip.z < -1.0 || projClip.z > 1.0) return baseColor;


                float2 texelSize = _ScreenParams.zw - 1.0;

                float depthR = SampleSceneDepth(uv + float2(texelSize.x, 0));
                float depthU = SampleSceneDepth(uv + float2(0, texelSize.y));
                float depthL = SampleSceneDepth(uv - float2(texelSize.x, 0));
                float depthD = SampleSceneDepth(uv - float2(0, texelSize.y));

                float maxDepthDiff = max(max(abs(rawDepth - depthR), abs(rawDepth - depthL)),
                                         max(abs(rawDepth - depthU), abs(rawDepth - depthD)));

                float edgeMask = step(maxDepthDiff, _EdgeFadeThreshold);

                // ★ Strength=0のとき強制的に元画像を返す確認
                //return baseColor;

                float2 tiledUV  = projClip.xy * 0.5 + 0.5;
                half4 projColor = SAMPLE_TEXTURE2D(_ProjectorTex, sampler_ProjectorTex, tiledUV);

                // ✅ ライトカラーとアンビエントから影色を近似
                float3 mainLightColor = _MainLightColor.rgb;
                float3 ambientColor   = unity_AmbientSky.rgb;

                float3 shadowRatio = ambientColor / max(ambientColor + mainLightColor, 0.0001);

                float  cloudMask     = (1.0 - projColor.r) * edgeMask; // ✅ 反転：黒=影、白=影なし
                float3 shadowedColor = lerp(baseColor.rgb, baseColor.rgb * shadowRatio, cloudMask * _ProjectionStrength);

                // ✅ Strength=0のとき完全に元画像
                return half4(shadowedColor, 1.0);
                
            }
            ENDHLSL
        }
    }
    FallBack Off
}