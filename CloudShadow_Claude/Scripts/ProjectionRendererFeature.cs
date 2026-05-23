using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Rendering.RenderGraphModule;

public class ProjectionRendererFeature : ScriptableRendererFeature
{
    // =========================================================
    //  ★ インスペクタに表示されるフィールド（ここに全部書く）
    // =========================================================
    [Header("Projection Texture")]
    public Texture2D projectionTexture;

    [Header("Projector Transform")]
    public Vector3 projectorPosition = new Vector3(0, 20, 0);
    public Vector3 projectorRotation = new Vector3(90, 0, 0);

    [Header("Orthographic Projection")]
    public float orthoSize = 10f;
    public float nearClip = 0.1f;
    public float farClip = 200f;

    [Range(0f, 1f)]
    public float strength = 1.0f;

    [Header("Artifact Reduction")]

    [Range(0f, 0.1f)] public float edgeFadeThreshold = 0.01f;

    // =========================================================
    //  内部変数
    // =========================================================
    ProjectionRenderPass _pass;

    // =========================================================
    //  ScriptableRendererFeature の実装
    // =========================================================
    public override void Create()
    {
        _pass = new ProjectionRenderPass
        {
            // ✅ AfterRenderingOpaques → 深度が確定した後
            //renderPassEvent = RenderPassEvent.AfterRenderingOpaques
            // ✅ AfterRenderingOpaques → AfterRendering に変更
            renderPassEvent = RenderPassEvent.AfterRendering

        };
    }

    public override void AddRenderPasses(ScriptableRenderer renderer,
                                     ref RenderingData renderingData)
    {
        // ✅ nullチェックを削除（Textureなしでも実行）
        // if (projectionTexture == null) return;

        Quaternion baseRotation = Quaternion.Euler(-90f, 0f, 0f);
        Quaternion extraRotation = Quaternion.Euler(projectorRotation);
        Quaternion rotation = extraRotation * baseRotation;

        _pass.Setup(
            projectionTexture,  // nullでも渡す
            projectorPosition,
            rotation,
            orthoSize, nearClip, farClip, strength,
            edgeFadeThreshold
        );

        renderer.EnqueuePass(_pass);
    }

    protected override void Dispose(bool disposing)
    {
        _pass?.Dispose();
    }

    // =========================================================
    //  Render Pass（内部クラス）
    // =========================================================
    class ProjectionRenderPass : ScriptableRenderPass, System.IDisposable
    {
        static readonly int ID_ProjectorVP = Shader.PropertyToID("_ProjectorVP");
        static readonly int ID_ProjectorTex = Shader.PropertyToID("_ProjectorTex");
        static readonly int ID_Strength = Shader.PropertyToID("_ProjectionStrength");

        // PropertyID追加
        static readonly int ID_EdgeFadeThreshold = Shader.PropertyToID("_EdgeFadeThreshold");

        Material _material;
        Texture2D _texture;
        Vector3 _position;
        Quaternion _rotation;
        float _orthoSize, _near, _far, _strength;
        float _borderFade;
        float _edgeFadeThreshold;

        public ProjectionRenderPass()
        {
            var shader = Shader.Find("Hidden/ProjectionFullscreen");
            if (shader == null)
            {
                Debug.LogError("[Projection] Shader 'Hidden/ProjectionFullscreen' が見つかりません。" +
                               "シェーダーファイルの1行目を確認してください。");
                return;
            }
            _material = CoreUtils.CreateEngineMaterial(shader);
        }

        public void Setup(Texture2D tex,
                          Vector3 position, Quaternion rotation,
                          float orthoSize, float near, float far, float strength,
                          float edgeFadeThreshold)
        {
            _texture = tex;
            _position = position;
            _rotation = rotation;
            _orthoSize = orthoSize;
            _near = near;
            _far = far;
            _strength = strength;
            _edgeFadeThreshold = edgeFadeThreshold; // ✅ 追加
        }

        void UpdateShaderProperties(Camera mainCam)
        {
            // ✅ テクスチャのWrapModeをRepeatに設定
            if (_texture != null)
                _texture.wrapMode = TextureWrapMode.Repeat;

            Matrix4x4 zFlip = Matrix4x4.Scale(new Vector3(1, 1, -1));
            Matrix4x4 viewMat = zFlip * Matrix4x4.TRS(
                                    _position, _rotation, Vector3.one).inverse;

            float s = _orthoSize;
            float near = _near;
            float far = _far;

            Matrix4x4 projMat = Matrix4x4.identity;
            projMat.m00 = 1f / s;
            projMat.m11 = 1f / s;
            projMat.m22 = -2f / (far - near);
            projMat.m23 = -(far + near) / (far - near);
            projMat.m33 = 1f;

            Matrix4x4 projectorVP = projMat * viewMat;

            // ✅ _InvVP は不要になったので削除
            _material.SetMatrix(ID_ProjectorVP, projectorVP);
            _material.SetTexture(ID_ProjectorTex, _texture);
            _material.SetFloat(ID_Strength, _strength);


            _material.SetFloat(ID_EdgeFadeThreshold, _edgeFadeThreshold);
        }

        public override void RecordRenderGraph(RenderGraph renderGraph,
                                       ContextContainer frameData)
        {
            var resourceData = frameData.Get<UniversalResourceData>();
            var cameraData = frameData.Get<UniversalCameraData>();

            if (cameraData.camera.cameraType == CameraType.Preview) return;

            // ✅ activeDepthTexture の代わりに cameraDepthTexture を使う
            TextureHandle depthHandle = resourceData.cameraDepthTexture;

            if (!depthHandle.IsValid())
            {
                Debug.LogWarning("[Projection] cameraDepthTexture is not valid!");
                return;
            }

            //Debug.Log("[Projection] cameraDepthTexture is valid!");

            UpdateShaderProperties(cameraData.camera);

            using var builder = renderGraph.AddUnsafePass<PassData>(
                "Projection Fullscreen Pass", out var passData);

            passData.material = _material;
            passData.colorTarget = resourceData.activeColorTexture;
            passData.depthTex = depthHandle;  // ✅ cameraDepthTexture を使う

            builder.UseTexture(depthHandle, AccessFlags.Read);
            builder.UseTexture(resourceData.activeColorTexture, AccessFlags.ReadWrite);

            builder.SetRenderFunc((PassData data, UnsafeGraphContext ctx) =>
            {
                CommandBuffer cmd = CommandBufferHelpers.GetNativeCommandBuffer(ctx.cmd);

                // ✅ _BlitTexture の設定を削除
                // DrawProceduralはカラーバッファを直接読めないため
                cmd.SetGlobalTexture("_CameraDepthTexture", data.depthTex);

                cmd.DrawProcedural(
                    Matrix4x4.identity,
                    data.material,
                    0,
                    MeshTopology.Triangles,
                    3
                );
            });
        }

        class PassData
        {
            public Material material;
            public TextureHandle colorTarget;
            public TextureHandle depthTex;
        }

        public void Dispose()
        {
            if (_material != null)
                CoreUtils.Destroy(_material);
        }
    }
}