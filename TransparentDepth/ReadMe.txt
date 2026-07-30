## 元シェーダーの仕組み(前提)

`Transparent/Diffuse ZWrite` は実質2パス構成です。

1. **深度のみパス**(`ZWrite On` + `ColorMask 0`):カラーは書かずデプスバッファだけ更新
2. **通常の半透明パス**(`UsePass "Transparent/Diffuse/FORWARD"`、`ZWrite Off` がデフォルト):普通にアルファブレンドで描画

この2段構成にする理由は、**「深度バッファには最終的に一番手前のピクセルの深さだけが残る」**という性質を使い、自己重なり(木の葉のクロスポリゴンや両面ポリゴンなど)で同じピクセルに複数フラグメントが重なったときに、最前面のフラグメントだけを2パス目でブレンドさせ、二重ブレンド(色が濃く/暗くなる)を防ぐためです。また、深度が正しく書き込まれることで、他の不透明・半透明オブジェクトとの前後関係も正しくなります。

URP/Shader Graphでこれを再現する方法は用途によって2通りあります。

---

## 方法A:お手軽(単一グラフで完結、ただし制限あり)

Shader Graphの **Graph Settings → Surface Options** に、Surface Type = Transparent にすると出てくる項目があります。

- **Depth Write**:`Auto` / `Force Enabled` / `Force Disabled`
- **Depth Test**:`LEqual`(デフォルト)など

これを `Depth Write = Force Enabled` にするだけで、ZWriteが強制的にONになったTransparentシェーダーになります。ウィンドウガラス・単一面の板ポリなど、自己重なりがないオブジェクトなら十分これで解決します。

⚠️ 注意点:これはあくまで**1パスの中でZWriteをONにするだけ**なので、元シェーダーの「深度専用パス→カラーパス」という2段構成とは挙動が異なります。同一メッシュ内で重なり合うポリゴン(木の葉のクロス板ポリなど)がある場合、描画順によっては二重ブレンドが残ることがあります。実際にUnityフォーラムでも「Depth WriteをForce Enabledにしたらアルファ周りで問題が出た」という報告があります。

---

## 方法B:完全再現(推奨・木や草などの自己重なりがある場合)

URPでは1つのシェーダー(Shader Graph)の中に「深度専用パス+通常パス」を両方視覚的に組むことはできません。そこで、**深度だけを書く極小のコードシェーダー**を1つ用意し、**Render Objects(Renderer Feature)** で「本番の半透明パスより前に、深度だけ書き込むパスとして描画する」構成にします。これなら見た目はShader Graphで自由に編集でき、技法だけ元シェーダーと同じにできます。

### 1. 深度専用マテリアル(1回作れば使い回せます)

```hlsl
Shader "Hidden/DepthOnlyColorMaskZero"
{
    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" "Queue"="Transparent" }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="SRPDefaultUnlit" }

            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull Off // 本体側のCull設定と合わせてください

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes { float4 positionOS : POSITION; };
            struct Varyings   { float4 positionHCS : SV_POSITION; };

            Varyings vert (Attributes IN)
            {
                Varyings OUT;
                OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz);
                return OUT;
            }

            half4 frag (Varyings IN) : SV_Target { return 0; }
            ENDHLSL
        }
    }
}
```

これでマテリアルを1つ作成(例:`M_DepthOnly`)。

### 2. 本体側は普通にShader Graphで作る

- Graph Settings:Surface Type = **Transparent**
- Depth Write は **Auto**(デフォルトのまま、ZWrite Offでよい)
- 見た目(Base Color × テクスチャ、Alphaなど)は自由に組む

### 3. 対象オブジェクトを専用レイヤーに置く

例:`TransparentZWrite` というレイヤーを新規作成し、木や草などのGameObjectをそこに設定。

### 4. Universal Renderer Data に Render Objects を追加

Renderer Asset(`.asset`, Universal Renderer Data)のInspectorで **Add Renderer Feature → Render Objects** を選び、以下を設定:

| 項目 | 設定値 |
|---|---|
| Event | `BeforeRenderingTransparents` |
| Filters → Layer Mask | `TransparentZWrite` |
| Filters → Queue | `Transparent` |
| Overrides → Material | 有効化し、`M_DepthOnly` を指定 |

これで「深度だけ書き込むパス → 通常の半透明パス」という元シェーダーと同じ順序・同じ効果(ZWrite On + ColorMask 0 → ZWrite Off の半透明ブレンド)が、Shader Graphの見た目を保ったまま再現できます。

---

## まとめ

| 用途 | 方法 |
|---|---|
| 単純な板・ガラスなど自己重なりなし | 方法A:Graph SettingsでDepth Write = Force Enabled |
| 木・草・クロス板ポリなど自己重なりあり(元シェーダーと完全に同じ挙動が必要) | 方法B:深度専用マテリアル + Render Objects |

Fallbackの `Transparent/VertexLit` やタグの `IgnoreProjector`/`RenderType` はURPでは使われない/自動処理されるので、Shader GraphでSurface Type = Transparentを選ぶだけで対応済みです。



## Q1. DepthOnlyColorMaskZero を Shader Graph で書けるか

結論:**書けます**。ただし Shader Graph の Graph Settings には `ColorMask` を直接指定する項目がありません(これはノードとしての「Color Mask」とは別物で、レンダーステートのColorMaskはUIに露出していません)。そこで **「Alphaを常に0にして通常のアルファブレンドに任せる」** というトリックでColorMask 0と同じ見た目の結果を作ります。

`Blend SrcAlpha OneMinusSrcAlpha` の場合、SrcAlpha = 0 なら

```
最終色 = Src色 × 0 + Dst色 × (1 - 0) = Dst色（変化なし）
```

となり、カラーバッファは一切変更されません。つまり **Alpha出力を0に固定するだけで、実質的にColorMask 0と同じ効果** が得られます。

### 作り方

1. `Create → Shader Graph → URP → Unlit Shader Graph` を作成(ライティング不要なのでUnlitでOK)
2. **Graph Settings**(Graph Inspector)で以下を設定
   - Surface Type: **Transparent**
   - Blend Mode: **Alpha**
   - Render Face: 本体マテリアルと同じCull設定に揃える(重要。ずれると深度だけ描かれない/余分に描かれる箇所ができる)
   - Depth Write: **Force Enabled**
   - Depth Test: **LEqual**
   - Alpha Clipping: オフ
3. Master Stack
   - **Alpha** に Float(定数) `0` を接続
   - Base Color は何でもよい(表示されないため黒でOK)

これでマテリアル化すれば、深度だけ書いてカラーバッファを一切汚さない「DepthOnlyColorMaskZero」相当のマテリアルがShader Graphだけで完結します。

---

## Q2. 同じオブジェクトに貼って Renderer Feature の代わりにできるか

結論:**できます**。しかもこちらの方が元のシェーダーの使い勝手(マテリアルをアサインするだけ)に近くなります。

Unityの MeshRenderer / SkinnedMeshRenderer は、**サブメッシュ数より Materials 配列の要素数が多い場合、余った分は最後のサブメッシュを配列の順番で重ねて複数回描画する**という公式仕様があります(アウトラインシェーダーの「シェル法」でよく使われるテクニックと同じ仕組みです)。

> If there are more materials than there are sub-meshes, Unity renders the last sub-mesh with each of the remaining materials, one on top of the next.

これを使えば:

- **Materials[0]** = 上で作った `DepthOnlyColorMaskZero`
- **Materials[1]** = 本体の半透明 Diffuse マテリアル(Depth Write は Auto=Off のまま)

とMesh Rendererの Materials 配列に2つ並べるだけで、「深度だけ書く → 通常のアルファブレンド」という元シェーダーと同じ描画順が、**Renderer Feature もレイヤー分けも無しで**再現できます。描画順は配列のインデックス順(0→1)です。

### 注意点

- この仕組みが効くのは**サブメッシュが1つだけのメッシュ**の場合です(単純な板ポリ・Plane・多くの木や草のカードメッシュなど)。元々複数マテリアル(複数サブメッシュ)を持つ複雑なメッシュだと、余ったマテリアルは「最後のサブメッシュ」にしか重ならないため、全サブメッシュに同じ処理をしたい場合はこの方法は使えません(その場合は前回案内した Renderer Feature 方式の方が安全です)。
- 描画コストは元シェーダーと同じく**2回分のドローコール**になります(オブジェクト単位で見た目のトレードオフは元と同等)。
- Cull設定を両マテリアルで揃えておかないと、深度パスと色パスで描画されるピクセルの位置がズレて、隙間や余分な塗りつぶしが出ることがあります。

### まとめ

| 方法 | 特徴 |
|---|---|
| Renderer Feature(前回案内) | レイヤー単位で一括適用、多数のプレハブに横断的に効かせたい場合向き |
| **Materials配列に2枚重ね(今回)** | プレハブ単体で完結、元シェーダーのように「マテリアルを差し替えるだけ」の感覚に一番近い |

単一サブメッシュの木・草・板ポリのような対象であれば、**今回のMaterials配列方式が最もシンプルで元のシェーダーの使用感に近い**のでおすすめです。