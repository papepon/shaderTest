Shader "Hidden/FakeShadow"
{
    Properties
    {
        // Blitter が要求するソーステクスチャ（自動設定）
        _BlitTexture("Source", 2D) = "white" {}
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
            Name "FakeShadow"
            ZTest Always  ZWrite Off  Cull Off
            Blend Off

            HLSLPROGRAM
            #pragma vertex   Vert
            #pragma fragment Frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            // ── テクスチャ・サンプラー ──────────────────
            TEXTURE2D_X_FLOAT(_CameraDepthTexture);   // ← _FLOAT を明示
            SAMPLER(sampler_CameraDepthTexture);

            TEXTURE2D(_ShadowTex);
            SAMPLER(sampler_ShadowTex);   // Wrap=Repeat にしておくとタイリング可

            // ── パラメータ ──────────────────────────────
            float4x4 _InvVP;
            float    _WorldScale;
            float4   _WorldOffset;
            float4   _ScrollOffset;
            float    _Intensity;
            float4   _ShadowColor;
            float    _ExcludeSky;

            // ── ワールド座標復元 ────────────────────────
            float3 ReconstructWorldPos(float2 uv, float rawDepth)
            {
                // UV → NDC
                float4 ndc = float4(uv.x * 2.0 - 1.0,
                                    uv.y * 2.0 - 1.0,
                                    rawDepth,
                                    1.0);
                float4 worldPos = mul(_InvVP, ndc);
                return worldPos.xyz / worldPos.w;
            }

            // ── フラグメントシェーダー ───────────────────
            half4 Frag(Varyings input) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

                float2 uv = input.texcoord;

                // ── シーンカラー取得
                half4 sceneColor = SAMPLE_TEXTURE2D_X(_BlitTexture,
                                                       sampler_LinearClamp, uv);

                // ── 深度取得
                float rawDepth = SAMPLE_TEXTURE2D_X(_CameraDepthTexture,
                                                    sampler_CameraDepthTexture,
                                                    uv).r;

                // ── スカイボックス判定（far plane）
                // Reversed-Z: depth=0 がfar、通常Z: depth=1 がfar
                #if UNITY_REVERSED_Z
                    bool isSky = rawDepth <= 0.0001;
                #else
                    bool isSky = rawDepth >= 0.9999;
                #endif

                if (isSky && _ExcludeSky > 0.5)
                    return sceneColor;

                // ── ワールド座標復元
                float3 worldPos = ReconstructWorldPos(uv, rawDepth);

                // ── XZ平面へのUV投影
                // worldScale [m] でタイリング、scrollOffset で雲の移動
                float2 shadowUV = (worldPos.xz
                                   + _WorldOffset.xy
                                   + _ScrollOffset.xy)
                                  / _WorldScale;

                // ── テクスチャサンプリング
                // 規約: 白=明るい(影なし) / 黒=影あり
                float shadowMask = SAMPLE_TEXTURE2D(_ShadowTex,
                                                    sampler_ShadowTex,
                                                    shadowUV).r;

                // ── 影合成
                // shadowMask=0(黒) → shadowColor に近づく
                // shadowMask=1(白) → そのまま
                float3 withShadow = lerp(_ShadowColor.rgb, sceneColor.rgb, shadowMask);
                float3 finalColor = lerp(sceneColor.rgb, withShadow, _Intensity);

                return half4(finalColor, sceneColor.a);
            }
            ENDHLSL
        }
    }
}