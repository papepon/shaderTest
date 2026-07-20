// ImpostorBaker: Normalベイク用シェーダー
//
// 元マテリアルの法線マップ(_BumpMap)を使ってワールド法線を計算し、
// それを「ベイクカメラのView空間」に変換してRGBエンコードして出力します。
//
// 固定視点でベイクする前提であれば、Plane側の見え方＝ベイクカメラの向きと一致するため、
// View空間法線をそのままPlaneのタンジェント空間法線として使い回せます
// （UNITY_MATRIX_V はレンダリング時点のカメラのビュー行列そのものです）。
//
// 元マテリアルに法線マップが設定されていない場合は、_BumpMap のデフォルト値 "bump"
// （Unity組み込みのフラットな法線テクスチャ）が使われるため、自動的にメッシュ法線
// そのものがベイクされます（追加の分岐は不要）。
Shader "Hidden/ImpostorBaker/BakeNormal"
{
    Properties
    {
        _BumpMap ("Normal Map", 2D) = "bump" {}
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }

        Pass
        {
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
                float3 normalOS   : NORMAL;
                float4 tangentOS  : TANGENT;
                float2 uv         : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv         : TEXCOORD0;
                float3 normalWS   : TEXCOORD1;
                float4 tangentWS  : TEXCOORD2; // xyz=tangent, w=sign
            };

            TEXTURE2D(_BumpMap);
            SAMPLER(sampler_BumpMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _BumpMap_ST;
            CBUFFER_END

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                OUT.positionCS = TransformObjectToHClip(IN.positionOS.xyz);
                OUT.uv = TRANSFORM_TEX(IN.uv, _BumpMap);
                OUT.normalWS = TransformObjectToWorldNormal(IN.normalOS);

                float3 tangentWS = TransformObjectToWorldDir(IN.tangentOS.xyz);
                // 負のスケール（左右反転したメッシュ等）に対応するための符号。
                OUT.tangentWS = float4(tangentWS, IN.tangentOS.w * unity_WorldTransformParams.w);

                return OUT;
            }

            float4 frag(Varyings IN) : SV_Target
            {
                float3 N = normalize(IN.normalWS);
                float3 T = normalize(IN.tangentWS.xyz);
                float3 B = cross(N, T) * IN.tangentWS.w;

                float3 tanNormal = UnpackNormal(SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, IN.uv));
                float3 worldNormal = normalize(tanNormal.x * T + tanNormal.y * B + tanNormal.z * N);

                // ベイクカメラのView空間へ変換。
                // カメラの方を向いている法線が (0,0,1) 付近になる想定です。
                float3 viewNormal = normalize(mul((float3x3)UNITY_MATRIX_V, worldNormal));

                // もし実機で確認した際に凹凸が反転して見える場合は、下の行の
                // コメントを外してZ軸を反転してください（環境によって符号が
                // 逆になるケースがあるための保険です）。
                // viewNormal.z *= -1;

                float3 encoded = viewNormal * 0.5 + 0.5;
                return float4(encoded, 1);
            }
            ENDHLSL
        }
    }
}
