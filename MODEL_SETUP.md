# Gemma 3n E2B Model Setup

This repository does not include the large model files required to run the application. To use the **Gemma 3n Modal Tutor**, you must download the model and load it into the app.

## 1. Download the Model

You need the **Gemma 3n E2B** (or similar compatible Gemma models) in the `.litertlm` format for mobile or WASM for Web.

- **Source**: [HuggingFace - Google Gemma](https://huggingface.co/google/gemma-3n-E2B-it-litert-lm/tree/main)
- **Model Type**: Gemma 3n E2B
- **Format**: 
  - **Native Mobile**: Look for the `.litertlm` or `.bin` files optimized for MediaPipe/LiteRT.
  - **Web**: Use the WASM-compatible versions provided by the `flutter_gemma` documentation.

## 2. Loading the Model into the App

Once you have the model file:

### On Mobile (Android/iOS)
1. Transfer the `.litertlm` file to your device.
2. Launch the application.
3. On the initialization screen, click **"Select Model File (.litertlm)"**.
4. Use the file picker to select your downloaded model.
5. The application will register and initialize the model locally.

### On Web
1. Place the model files in the `web/` directory if you are hosting it yourself.
2. Alternatively, use the in-app UI to register the model path if configured.

> [!IMPORTANT]
> Ensure you are using the **Native Mobile** version of the model for Android/iOS. Using a "Web" version on a mobile device will result in an "Invalid magic number" error.

## Troubleshooting

- **Magic Number Error**: This usually means you are trying to load a Web/WASM model on a mobile device or vice-versa.
- **Initialization Hangs**: Ensure your device has enough RAM to load the model (Gemma 3n E4B typically requires 4GB+ of free memory).
- **Clear Cache**: If you want to switch models, use the **"Clear Cache & Reset"** button on the home screen.
