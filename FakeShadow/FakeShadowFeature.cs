using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Rendering.RenderGraphModule;

// ─────────────────────────────────────────────
//  RendererFeature
// ─────────────────────────────────────────────
public class FakeShadowFeature : ScriptableRendererFeature
{
    [System.Serializable]
    public class Settings
    {
        [Header("Shadow Texture")]
        [Tooltip("黒=影あり / 白=影なし")]
        public Texture2D shadowTexture;

        [Header("Projection")]
        public float worldScale = 30f;
        public Vector2 worldOffset = Vector2.zero;

        [Header("Animation")]
        public Vector2 scrollSpeed = Vector2.zero;

        [Header("Appearance")]
        [Range(0f, 1f)] public float intensity = 0.6f;
        public Color shadowColor = new Color(0f, 0f, 0f, 1f);

        [Header("Filter")]
        public bool excludeSky = true;
    }

    public Settings settings = new();
    FakeShadowPass _pass;
    Material _material;

    public override void Create()
    {
        _material = CoreUtils.CreateEngineMaterial("Hidden/FakeShadow");
        _pass = new FakeShadowPass(settings, _material)
        {
            renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing
        };
    }

    public override void AddRenderPasses(ScriptableRenderer renderer,
                                         ref RenderingData renderingData)
    {
        if (settings.shadowTexture == null || _material == null) return;
        var t = renderingData.cameraData.cameraType;
        if (t == CameraType.Preview || t == CameraType.Reflection) return;
        renderer.EnqueuePass(_pass);
    }

    protected override void Dispose(bool disposing)
    {
        _pass?.Dispose();
        CoreUtils.Destroy(_material);
    }
}

// ─────────────────────────────────────────────
//  RenderPass（Render Graph 専用）
// ─────────────────────────────────────────────
public class FakeShadowPass : ScriptableRenderPass, System.IDisposable
{
    readonly FakeShadowFeature.Settings _settings;
    readonly Material _material;
    Vector2 _scrollAccum;

    static readonly int ID_DepthTex = Shader.PropertyToID("_CameraDepthTexture");
    static readonly int ID_ShadowTex = Shader.PropertyToID("_ShadowTex");
    static readonly int ID_WorldScale = Shader.PropertyToID("_WorldScale");
    static readonly int ID_WorldOffset = Shader.PropertyToID("_WorldOffset");
    static readonly int ID_ScrollOffset = Shader.PropertyToID("_ScrollOffset");
    static readonly int ID_Intensity = Shader.PropertyToID("_Intensity");
    static readonly int ID_ShadowColor = Shader.PropertyToID("_ShadowColor");
    static readonly int ID_ExcludeSky = Shader.PropertyToID("_ExcludeSky");
    static readonly int ID_InvVP = Shader.PropertyToID("_InvVP");

    class PassData
    {
        public TextureHandle src;
        public TextureHandle depth;
        public Material material;
    }

    public FakeShadowPass(FakeShadowFeature.Settings s, Material mat)
    {
        _settings = s;
        _material = mat;
    }

    void UpdateMaterial(Camera cam)
    {
        _scrollAccum += _settings.scrollSpeed * Time.deltaTime;

        var vp = GL.GetGPUProjectionMatrix(cam.projectionMatrix, true)
                 * cam.worldToCameraMatrix;

        _material.SetMatrix(ID_InvVP, vp.inverse);
        _material.SetTexture(ID_ShadowTex, _settings.shadowTexture);
        _material.SetFloat(ID_WorldScale, _settings.worldScale);
        _material.SetVector(ID_WorldOffset,
            new Vector4(_settings.worldOffset.x, _settings.worldOffset.y, 0, 0));
        _material.SetVector(ID_ScrollOffset,
            new Vector4(_scrollAccum.x, _scrollAccum.y, 0, 0));
        _material.SetFloat(ID_Intensity, _settings.intensity);
        _material.SetColor(ID_ShadowColor, _settings.shadowColor);
        _material.SetFloat(ID_ExcludeSky, _settings.excludeSky ? 1f : 0f);
    }

    public override void RecordRenderGraph(RenderGraph renderGraph,
                                           ContextContainer frameData)
    {
        var resourceData = frameData.Get<UniversalResourceData>();
        var cameraData = frameData.Get<UniversalCameraData>();

        if (cameraData.cameraType is CameraType.Preview or CameraType.Reflection) return;

        var src = resourceData.activeColorTexture;
        var depth = resourceData.cameraDepthTexture;

        if (!src.IsValid() || !depth.IsValid()) return;

        UpdateMaterial(cameraData.camera);

        // src と同仕様の出力バッファを作成
        var desc = renderGraph.GetTextureDesc(src);
        desc.name = "_FakeShadowDest";
        desc.clearBuffer = false;
        var dest = renderGraph.CreateTexture(desc);

        using (var builder = renderGraph.AddRasterRenderPass<PassData>(
                   "FakeShadow", out var passData))
        {
            passData.src = src;
            passData.depth = depth;
            passData.material = _material;

            builder.SetRenderAttachment(dest, 0, AccessFlags.Write);
            builder.UseTexture(src, AccessFlags.Read);
            builder.UseTexture(depth, AccessFlags.Read);

            // SetGlobalTexture(TextureHandle) を使うために必要
            builder.AllowGlobalStateModification(true);

            builder.SetRenderFunc((PassData data, RasterGraphContext ctx) =>
            {
                // 深度テクスチャをシェーダーへバインド
                // RasterCommandBuffer は SetGlobalTexture(TextureHandle) に対応
                ctx.cmd.SetGlobalTexture(ID_DepthTex, data.depth);

                // ポイント：Blitter.BlitTexture(RasterCommandBuffer, TextureHandle, ...)
                // → 内部で MaterialPropertyBlock に _BlitTexture をバインドするため
                //   SetGlobalTexture より確実にシェーダーへ届く
                Blitter.BlitTexture(ctx.cmd,
                                    data.src,
                                    new Vector4(1f, 1f, 0f, 0f),
                                    data.material,
                                    pass: 0);
            });
        }

        // カメラ出力を差し替え（dest への書き込みが反映される）
        resourceData.cameraColor = dest;
    }

    public void Dispose() { }
}