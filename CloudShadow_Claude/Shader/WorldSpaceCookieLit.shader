// URPカスタムLitシェーダー（抜粋）
Shader "Custom/WorldSpaceCookieLit"
{
    Properties
    {
        _CookieTex ("Cookie Texture", 2D) = "white" {}
        _BaseColor ("Base Color", Color) = (1,1,1,1)
        _CookieScale ("Cookie Scale", Float) = 1.0
        _CookieOffsetX ("Cookie Offset X", Float) = 0.0
        _CookieOffsetZ ("Cookie Offset Z", Float) = 0.0
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }
            ColorMask 0
            ZWrite On

            HLSLPROGRAM
            #pragma vertex vertShadow
            #pragma fragment fragShadow
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct ShadowAttributes
            {
                float4 positionOS : POSITION;
            };

            struct ShadowVaryings
            {
                float4 positionHCS : SV_POSITION;
            };

            ShadowVaryings vertShadow(ShadowAttributes IN)
            {
                ShadowVaryings OUT;
                OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz);
                return OUT;
            }

            half4 fragShadow(ShadowVaryings IN) : SV_Target
            {
                // Depth-only shadow caster; color output is ignored.
                return half4(0,0,0,0);
            }
            ENDHLSL
        }

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_CookieTex);
            SAMPLER(sampler_CookieTex);

            CBUFFER_START(UnityPerMaterial)
                float4 _CookieTex_ST;
                float4 _BaseColor;
                float _CookieScale;
                float _CookieOffsetX;
                float _CookieOffsetZ;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float3 positionWS  : TEXCOORD0;
                float3 normalWS    : TEXCOORD1;
            };

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                OUT.positionWS = TransformObjectToWorld(IN.positionOS.xyz);
                OUT.positionHCS = TransformWorldToHClip(OUT.positionWS);
                OUT.normalWS = TransformObjectToWorldNormal(IN.normalOS);
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                // ワールドX,Z座標からUVを生成
                float2 cookieUV = float2(
                    IN.positionWS.x * _CookieScale + _CookieOffsetX,
                    IN.positionWS.z * _CookieScale + _CookieOffsetZ
                );
                half4 cookie = SAMPLE_TEXTURE2D(_CookieTex, sampler_CookieTex, cookieUV);

                // メインライトを取得（影の減衰も含む）
                Light mainLight = GetMainLight(TransformWorldToShadowCoord(IN.positionWS));

                // ライトのattenuationにCookieを掛ける
                half cookieMask = cookie.r; // グレースケール想定
                half3 lightColor = mainLight.color * mainLight.distanceAttenuation
                                 * mainLight.shadowAttenuation  // ← 影の減衰
                                 * cookieMask;                  // ← Cookieを乗算

                // 通常のAlbedo
                SurfaceData surfaceData = (SurfaceData)0;
                surfaceData.albedo = _BaseColor.rgb;
                surfaceData.alpha = 1.0;

                // 最終カラー = Albedo × ライト(影+Cookie込み)
                half3 finalColor = surfaceData.albedo * lightColor;

                return half4(finalColor, 1.0);
            }
            ENDHLSL
        }
    }
}