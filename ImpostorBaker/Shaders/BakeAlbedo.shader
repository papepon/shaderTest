// ImpostorBaker: Albedoベイク用シェーダー
// 対象オブジェクトの元マテリアルが持つ _BaseMap / _BaseColor をそのまま出力するだけの
// シンプルなUnlitシェーダーです。ImpostorBakerWindow が実行時に一時的に各Rendererへ
// 割り当て、固定視点カメラでレンダリングしてAlbedoテクスチャとして焼き出します。
Shader "Hidden/ImpostorBaker/BakeAlbedo"
{
    Properties
    {
        _BaseMap ("Base Map", 2D) = "white" {}
        _BaseColor ("Base Color", Color) = (1,1,1,1)
        _Cutoff ("Alpha Cutoff", Range(0,1)) = 0.0
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }

        Pass
        {
            // URPの標準Forwardレンダラーに確実に拾ってもらうためのタグ。
            // Lit/SimpleLit等のURP独自パスを使わない簡易シェーダーの定番タグです。
            Tags { "LightMode"="SRPDefaultUnlit" }

            Cull Off
            ZWrite On
            ZTest LEqual

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv         : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv         : TEXCOORD0;
            };

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                float4 _BaseColor;
                float  _Cutoff;
            CBUFFER_END

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                OUT.positionCS = TransformObjectToHClip(IN.positionOS.xyz);
                OUT.uv = TRANSFORM_TEX(IN.uv, _BaseMap);
                return OUT;
            }

            float4 frag(Varyings IN) : SV_Target
            {
                float4 tex = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv);
                float4 col = tex * _BaseColor;

                // 葉っぱなどアルファ抜きされている元マテリアルと見た目を合わせたい場合、
                // ここでclipしておくと輪郭が綺麗に出ます（不要ならCutoffを0のままに）。
                clip(col.a - _Cutoff);

                return col;
            }
            ENDHLSL
        }
    }
}
