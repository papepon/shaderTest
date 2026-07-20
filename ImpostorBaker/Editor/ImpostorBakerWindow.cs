// ImpostorBaker: 固定視点インポスター（Albedo/Normal）ベイクツール
//
// 使い方:
// 1. Scene上に「ベイク用カメラ」を1つ用意し、実際にPlaneを表示したい固定アングルに
//    合わせて位置・向きを調整する（Game viewでプレビューしながら決めるとよい）。
// 2. Tools > Impostor Baker を開き、対象オブジェクトとこのカメラを指定する。
// 3. Bakeボタンを押すと、カメラの向きは維持したまま自動でOrthographic/距離/サイズを
//    対象オブジェクトのバウンズにフィットさせ、Albedo/Normalの2枚のPNGを書き出す。
// 4. ベイク後、カメラの姿勢・元のマテリアルは自動的に元へ戻る。
using System.IO;
using UnityEditor;
using UnityEngine;
using UnityEngine.Rendering.Universal;

namespace ImpostorBaker
{
    public class ImpostorBakerWindow : EditorWindow
    {
        private GameObject targetObject;
        private Camera bakeCamera;
        private int resolution = 1024;
        private float boundsPadding = 1.05f;
        private string outputFolder = "Assets/ImpostorBakes";
        private string baseFileName = "Impostor";

        private Shader albedoBakeShader;
        private Shader normalBakeShader;

        private static readonly int[] ResolutionValues = { 512, 1024, 2048, 4096 };
        private static readonly string[] ResolutionLabels = { "512", "1024", "2048", "4096" };

        [MenuItem("Tools/Impostor Baker")]
        public static void ShowWindow()
        {
            GetWindow<ImpostorBakerWindow>("Impostor Baker");
        }

        private void OnEnable()
        {
            albedoBakeShader = Shader.Find("Hidden/ImpostorBaker/BakeAlbedo");
            normalBakeShader = Shader.Find("Hidden/ImpostorBaker/BakeNormal");
        }

        private void OnGUI()
        {
            EditorGUILayout.LabelField("対象", EditorStyles.boldLabel);
            targetObject = (GameObject)EditorGUILayout.ObjectField(
                "対象オブジェクト", targetObject, typeof(GameObject), true);
            bakeCamera = (Camera)EditorGUILayout.ObjectField(
                "ベイク用カメラ（Scene上に配置し向きを合わせておく）", bakeCamera, typeof(Camera), true);

            EditorGUILayout.Space();
            EditorGUILayout.LabelField("設定", EditorStyles.boldLabel);
            resolution = EditorGUILayout.IntPopup("解像度", resolution, ResolutionLabels, ResolutionValues);
            boundsPadding = EditorGUILayout.Slider("余白（バウンズ倍率）", boundsPadding, 1.0f, 1.5f);
            outputFolder = EditorGUILayout.TextField("出力フォルダ", outputFolder);
            baseFileName = EditorGUILayout.TextField("ファイル名（接頭辞）", baseFileName);

            EditorGUILayout.Space();

            if (albedoBakeShader == null || normalBakeShader == null)
            {
                EditorGUILayout.HelpBox(
                    "BakeAlbedo / BakeNormal シェーダーが見つかりません。" +
                    "Shaders フォルダがプロジェクトに含まれているか確認してください。",
                    MessageType.Error);
            }

            bool canBake = targetObject != null && bakeCamera != null
                           && albedoBakeShader != null && normalBakeShader != null;

            using (new EditorGUI.DisabledScope(!canBake))
            {
                if (GUILayout.Button("Bake", GUILayout.Height(32)))
                {
                    Bake();
                }
            }

            EditorGUILayout.HelpBox(
                "ベイク後、Albedo画像のImport Settingsは自動でsRGB/AlphaIsTransparencyに、" +
                "Normal画像は自動でTexture Type = Normal Mapに設定されます。",
                MessageType.Info);
        }

        private void Bake()
        {
            var renderers = targetObject.GetComponentsInChildren<Renderer>();
            if (renderers.Length == 0)
            {
                Debug.LogError("[ImpostorBaker] 対象オブジェクトにRendererが見つかりません。");
                return;
            }

            Bounds bounds = renderers[0].bounds;
            foreach (var r in renderers) bounds.Encapsulate(r.bounds);

            // --- カメラの状態を退避 ---
            Vector3 originalPosition = bakeCamera.transform.position;
            Quaternion originalRotation = bakeCamera.transform.rotation;
            bool originalOrtho = bakeCamera.orthographic;
            float originalOrthoSize = bakeCamera.orthographicSize;
            float originalNear = bakeCamera.nearClipPlane;
            float originalFar = bakeCamera.farClipPlane;
            RenderTexture originalTargetTexture = bakeCamera.targetTexture;
            CameraClearFlags originalClearFlags = bakeCamera.clearFlags;
            Color originalBackgroundColor = bakeCamera.backgroundColor;
            bool originalAllowHDR = bakeCamera.allowHDR;

            // URPはHDRやPost Processingが有効だと、内部バッファがアルファ非対応の
            // フォーマットになりアルファが失われることがあるため、ベイク中は明示的にOFFにする。
            UniversalAdditionalCameraData additionalCameraData = bakeCamera.GetUniversalAdditionalCameraData();
            bool originalPostProcessing = additionalCameraData.renderPostProcessing;

            Material[][] originalMaterials = new Material[renderers.Length][];
            for (int i = 0; i < renderers.Length; i++)
                originalMaterials[i] = renderers[i].sharedMaterials;

            try
            {
                FitCameraToBounds(bakeCamera, bounds, boundsPadding, originalRotation);

                bakeCamera.clearFlags = CameraClearFlags.SolidColor;
                bakeCamera.backgroundColor = new Color(0f, 0f, 0f, 0f);
                bakeCamera.allowHDR = false;
                additionalCameraData.renderPostProcessing = false;

                if (!Directory.Exists(outputFolder))
                    Directory.CreateDirectory(outputFolder);

                string albedoPath = Path.Combine(outputFolder, baseFileName + "_albedo.png");
                string normalPath = Path.Combine(outputFolder, baseFileName + "_normal.png");

                // --- Albedoパス ---
                ApplyBakeMaterials(renderers, originalMaterials, albedoBakeShader, "_BaseMap", "_BaseColor");
                RenderAndSave(bakeCamera, resolution, albedoPath, isDataTexture: false);

                // --- Normalパス ---
                ApplyBakeMaterials(renderers, originalMaterials, normalBakeShader, "_BumpMap", null);
                RenderAndSave(bakeCamera, resolution, normalPath, isDataTexture: true);

                // --- マテリアルを復元 ---
                for (int i = 0; i < renderers.Length; i++)
                    renderers[i].sharedMaterials = originalMaterials[i];

                AssetDatabase.Refresh();
                ConfigureImportSettings(albedoPath, isNormalMap: false);
                ConfigureImportSettings(normalPath, isNormalMap: true);

                Debug.Log("[ImpostorBaker] ベイク完了: " + outputFolder);
            }
            finally
            {
                // --- カメラを完全に元へ戻す ---
                bakeCamera.transform.position = originalPosition;
                bakeCamera.transform.rotation = originalRotation;
                bakeCamera.orthographic = originalOrtho;
                bakeCamera.orthographicSize = originalOrthoSize;
                bakeCamera.nearClipPlane = originalNear;
                bakeCamera.farClipPlane = originalFar;
                bakeCamera.targetTexture = originalTargetTexture;
                bakeCamera.clearFlags = originalClearFlags;
                bakeCamera.backgroundColor = originalBackgroundColor;
                bakeCamera.allowHDR = originalAllowHDR;
                additionalCameraData.renderPostProcessing = originalPostProcessing;
            }
        }

        /// <summary>
        /// カメラの「向き」は変えずに、バウンズにちょうど収まるよう
        /// Orthographic Size・距離・クリップ面を自動調整する。
        /// </summary>
        private static void FitCameraToBounds(Camera cam, Bounds bounds, float padding, Quaternion fixedRotation)
        {
            cam.orthographic = true;
            cam.transform.rotation = fixedRotation;

            Vector3 forward = cam.transform.forward;
            Vector3 up = cam.transform.up;
            Vector3 right = cam.transform.right;

            Vector3 center = bounds.center;
            Vector3 ext = bounds.extents;

            float maxRight = 0f, maxUp = 0f, maxForwardExtent = 0f;
            for (int i = 0; i < 8; i++)
            {
                Vector3 corner = new Vector3(
                    (i & 1) == 0 ? -ext.x : ext.x,
                    (i & 2) == 0 ? -ext.y : ext.y,
                    (i & 4) == 0 ? -ext.z : ext.z);

                maxRight = Mathf.Max(maxRight, Mathf.Abs(Vector3.Dot(corner, right)));
                maxUp = Mathf.Max(maxUp, Mathf.Abs(Vector3.Dot(corner, up)));
                maxForwardExtent = Mathf.Max(maxForwardExtent, Mathf.Abs(Vector3.Dot(corner, forward)));
            }

            float halfSize = Mathf.Max(maxRight, maxUp) * padding;
            cam.orthographicSize = Mathf.Max(halfSize, 0.001f);

            // バウンズを内包できる十分な距離までカメラを下げる。
            float distance = maxForwardExtent * padding + 1f;
            cam.transform.position = center - forward * distance;

            cam.nearClipPlane = 0.01f;
            cam.farClipPlane = distance + maxForwardExtent * padding + 1f;
        }

        /// <summary>
        /// 対象Rendererのマテリアルを、指定したベイク用シェーダーへ一時的に差し替える。
        /// 元マテリアルが持つメインテクスチャ（BaseMap/BumpMap）とタイリング設定、
        /// および色プロパティ（BaseColor）は極力引き継ぐ。
        /// </summary>
        private static void ApplyBakeMaterials(
            Renderer[] renderers, Material[][] originalMaterials,
            Shader bakeShader, string mainTexProperty, string colorProperty)
        {
            for (int i = 0; i < renderers.Length; i++)
            {
                Material[] src = originalMaterials[i];
                Material[] baked = new Material[src.Length];

                for (int m = 0; m < src.Length; m++)
                {
                    Material bakeMat = new Material(bakeShader);

                    Material s = src[m];
                    if (s != null)
                    {
                        if (!string.IsNullOrEmpty(mainTexProperty) && s.HasProperty(mainTexProperty))
                        {
                            Texture tex = s.GetTexture(mainTexProperty);
                            if (tex != null) bakeMat.SetTexture(mainTexProperty, tex);

                            string stProp = mainTexProperty + "_ST";
                            if (s.HasProperty(stProp))
                                bakeMat.SetVector(stProp, s.GetVector(stProp));
                        }

                        if (!string.IsNullOrEmpty(colorProperty) && s.HasProperty(colorProperty))
                            bakeMat.SetColor(colorProperty, s.GetColor(colorProperty));
                    }

                    baked[m] = bakeMat;
                }

                renderers[i].sharedMaterials = baked;
            }
        }

        private static void RenderAndSave(Camera cam, int size, string path, bool isDataTexture)
        {
            var desc = new RenderTextureDescriptor(size, size, RenderTextureFormat.ARGB32, 24)
            {
                // Albedo: sRGB(見た目通りの色) / Normal: Linear(生データとして正確に保持)
                sRGB = !isDataTexture,
                msaaSamples = 1
            };

            RenderTexture rt = RenderTexture.GetTemporary(desc);
            cam.targetTexture = rt;

            RenderTexture prevActive = RenderTexture.active;
            RenderTexture.active = rt;

            cam.Render();

            Texture2D tex = new Texture2D(size, size, TextureFormat.RGBA32, false, isDataTexture);
            tex.ReadPixels(new Rect(0, 0, size, size), 0, 0);
            tex.Apply();

            File.WriteAllBytes(path, tex.EncodeToPNG());

            RenderTexture.active = prevActive;
            cam.targetTexture = null;
            RenderTexture.ReleaseTemporary(rt);
            Object.DestroyImmediate(tex);
        }

        private static void ConfigureImportSettings(string path, bool isNormalMap)
        {
            AssetDatabase.ImportAsset(path);
            var importer = AssetImporter.GetAtPath(path) as TextureImporter;
            if (importer == null) return;

            importer.textureType = isNormalMap ? TextureImporterType.NormalMap : TextureImporterType.Default;
            importer.sRGBTexture = !isNormalMap;
            importer.alphaIsTransparency = !isNormalMap;
            importer.mipmapEnabled = true;
            importer.SaveAndReimport();
        }
    }
}
