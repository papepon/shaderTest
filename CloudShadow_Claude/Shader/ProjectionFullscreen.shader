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
            Blend  Off
            Cull   Off

            HLSLPROGRAM
            #pragma target   4.5
            #pragma vertex   Vert
            #pragma fragment Frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

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

            TEXTURE2D(_BlitTexture);      SAMPLER(sampler_BlitTexture);
            TEXTURE2D(_ProjectorTex);     SAMPLER(sampler_ProjectorTex);

            CBUFFER_START(UnityPerMaterial)
                float4 _BlitTexture_ST;
                float4 _ProjectorTex_ST;
                float  _ProjectionStrength;
                float4x4 _ProjectorVP;
                float4x4 _InvVP;
            CBUFFER_END

            half4 Frag(Varyings input) : SV_Target
            {
                float2 uv = input.texcoord;

                half4 baseColor = SAMPLE_TEXTURE2D(_BlitTexture, sampler_BlitTexture, uv);

                float rawDepth = SampleSceneDepth(uv);

                #if UNITY_REVERSED_Z
                    if (rawDepth <= 0.0001) return baseColor;
                #else
                    if (rawDepth >= 0.9999) return baseColor;
                #endif

                float3 worldPos = ComputeWorldSpacePosition(uv, rawDepth, UNITY_MATRIX_I_VP);

                float4 projClip = mul(_ProjectorVP, float4(worldPos, 1.0));

                // ✅ Near/FarClipをprojClip.zで判定
                // Orthographic行列変換後のZ値は[-1, 1]の範囲が有効
                if (projClip.z < -1.0 || projClip.z > 1.0) return baseColor;

                float2 tiledUV = frac(projClip.xy * 0.5 + 0.5);

                half4 projColor = SAMPLE_TEXTURE2D(_ProjectorTex, sampler_ProjectorTex, tiledUV);

                float blend = projColor.a * _ProjectionStrength;
                return half4(lerp(baseColor.rgb, projColor.rgb, blend), baseColor.a);
            }
            ENDHLSL
        }
    }
    FallBack Off
}