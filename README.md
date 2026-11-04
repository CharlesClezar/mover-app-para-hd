# Mover App para HD

App nativo para macOS (SwiftUI) que move aplicativos de `/Applications` (SSD) para uma pasta no HD e deixa um link simbólico no lugar, para o SSD não encher.

## Como funciona

Para cada `.app` arrastado:

```
ditto "/Applications/X.app" "<destino>/X.app"
rm -rf "/Applications/X.app"
ln -s "<destino>/X.app" "/Applications/X.app"
```

Se o app já estiver dentro da pasta de destino, só cria o link em `/Applications`.
A pasta de destino fica salva em `UserDefaults` (`local.mover-app-para-hd`, chave `destino`).

## Compilar

Requer Xcode Command Line Tools. Gera um app universal (Intel + Apple Silicon, macOS 13+):

```bash
./MoverApp/build.sh
```

O app sai em `Mover App para HD.app` na raiz do projeto. Na primeira abertura, clique com o botão direito → Abrir (app não assinado).
