import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GemmaApp());
}

class GemmaApp extends StatelessWidget {
  const GemmaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Gemma 3n Multimodal Tutor',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        primaryColor: const Color(0xFF0EA5E9),
      ),
      home: const ChatPage(),
    );
  }
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final List<ChatMessage> _messages = [
    ChatMessage(
      text:
          'Hello! I can now "see" images and "hear" audio. Try uploading a screenshot of a math problem or recording a question!',
      isUser: false,
    ),
  ];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();
  final AudioRecorder _audioRecorder = AudioRecorder();

  bool _isInitializing = true;
  bool _isSending = false;
  String _status = "Loading WASM & Native layers...";

  Uint8List? _selectedImageBytes;
  String? _recordedAudioPath;
  InferenceModelSession? _session;
  List<String> _installedModels = [];

  @override
  void initState() {
    super.initState();
    _setupGemma();
  }

  Future<void> _setupGemma() async {
    try {
      await FlutterGemma.initialize();
      await _refreshInstalledModels();
      _initModel();
    } catch (e) {
      setState(() {
        _status = "Error: $e";
        _isInitializing = false;
      });
    }
  }

  Future<void> _refreshInstalledModels() async {
    final models = await FlutterGemma.listInstalledModels();
    setState(() {
      _installedModels = models;
    });
  }

  Future<void> _initModel() async {
    try {
      if (!FlutterGemma.hasActiveModel()) {
        if (_installedModels.isEmpty) {
          setState(() {
            _status = "No model installed. Please select your .litertlm file.";
            _isInitializing = false;
          });
          return;
        } else {
          // Check if the installed model is a Web version (incompatible with mobile)
          final firstModel = _installedModels.first;
          if (firstModel.contains("-Web")) {
            setState(() {
              _status =
                  "Incompatible 'Web' model detected ($firstModel).\n"
                  "Please click 'Clear Cache & Reset' and use a native mobile model.";
              _isInitializing = false;
            });
            return;
          }
          // Auto-activate the first installed model
          await FlutterGemma.installModel(
            modelType: ModelType.gemmaIt,
          ).fromBundled(firstModel).install();
        }
      }

      // Check the active model for incompatibility before creating instances
      final manager = FlutterGemmaPlugin.instance.modelManager;
      final activeModelName = manager.activeInferenceModel?.name ?? "";
      if (activeModelName.contains("-Web")) {
        setState(() {
          _status =
              "Incompatible 'Web' model active ($activeModelName).\n"
              "Please click 'Clear Cache & Reset' and select a native mobile model.";
          _isInitializing = false;
        });
        return;
      }

      setState(() => _status = "Initializing with CPU...");

      final model = await FlutterGemmaPlugin.instance.createModel(
        modelType: ModelType.gemmaIt,
        maxTokens: 1024,
        supportImage: true,
        supportAudio: true,
        preferredBackend: PreferredBackend.gpu,
      );

      _session = await model.createSession(
        enableVisionModality: true,
        enableAudioModality: true,
        temperature: 0.7,
      );

      setState(() => _isInitializing = false);
    } catch (e) {
      String errorMsg = e.toString();
      if (errorMsg.contains("magic number")) {
        errorMsg =
            "INVALID MODEL FORMAT: Please use the native mobile version of the model, not the Web version.";
      }
      setState(() {
        _status = "Error: $errorMsg";
        _isInitializing = false;
      });
    }
  }

  Future<void> _pickModel() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.any,
    );
    if (result != null && result.files.single.path != null) {
      setState(() {
        _isInitializing = true;
        _status = "Registering model file...";
      });
      try {
        await FlutterGemma.installModel(
          modelType: ModelType.gemmaIt,
        ).fromFile(result.files.single.path!).install();
        await _refreshInstalledModels();
        _initModel();
      } catch (e) {
        setState(() {
          _status = "Error: $e";
          _isInitializing = false;
        });
      }
    }
  }

  Future<void> _clearModels() async {
    for (var m in _installedModels) {
      await FlutterGemma.uninstallModel(m);
    }
    await _refreshInstalledModels();
    setState(() => _status = "All models cleared.");
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      final bytes = await image.readAsBytes();
      setState(() {
        _selectedImageBytes = bytes;
      });
    }
  }

  Future<void> _toggleRecording() async {
    if (await _audioRecorder.isRecording()) {
      final path = await _audioRecorder.stop();
      setState(() {
        _recordedAudioPath = path;
      });
    } else {
      if (await Permission.microphone.request().isGranted) {
        final docs = await getApplicationDocumentsDirectory();
        final path = p.join(
          docs.path,
          'audio_${DateTime.now().millisecondsSinceEpoch}.m4a',
        );
        await _audioRecorder.start(const RecordConfig(), path: path);
        setState(() {});
      }
    }
  }

  Future<void> _handleChat() async {
    final text = _controller.text.trim();
    if ((text.isEmpty &&
            _selectedImageBytes == null &&
            _recordedAudioPath == null) ||
        _session == null) {
      return;
    }

    setState(() {
      _messages.add(
        ChatMessage(
          text: text,
          isUser: true,
          imageBytes: _selectedImageBytes,
          audioPath: _recordedAudioPath,
        ),
      );
      _isSending = true;
    });

    _controller.clear();
    _scrollToBottom();

    try {
      Uint8List? audioBytes;
      if (_recordedAudioPath != null) {
        audioBytes = await File(_recordedAudioPath!).readAsBytes();
      }

      final message = Message(
        text: text,
        isUser: true,
        imageBytes: _selectedImageBytes,
        audioBytes: audioBytes,
      );

      await _session!.addQueryChunk(message);

      String response = "";
      final aiMessage = ChatMessage(text: "", isUser: false);
      setState(() => _messages.add(aiMessage));

      await for (final chunk in _session!.getResponseAsync()) {
        response += chunk;
        setState(() {
          aiMessage.text = response;
        });
        _scrollToBottom();
      }
    } catch (e) {
      setState(() {
        _messages.add(ChatMessage(text: "Error: $e", isUser: false));
      });
    } finally {
      setState(() {
        _isSending = false;
        _selectedImageBytes = null;
        _recordedAudioPath = null;
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing || _session == null) {
      return Scaffold(
        body: Container(
          width: double.infinity,
          color: const Color(0xFF0F172A),
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 100),
                const Text(
                  "Initializing Gemma 3n E4B (Multimodal)",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _status,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF94A3B8)),
                ),
                const SizedBox(height: 30),
                if (_isInitializing)
                  const CircularProgressIndicator(color: Color(0xFF0EA5E9)),
                if (!_isInitializing) ...[
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0EA5E9),
                    ),
                    onPressed: _pickModel,
                    child: const Text(
                      "Select Model File (.litertlm)",
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                  if (_installedModels.isNotEmpty)
                    TextButton(
                      onPressed: _clearModels,
                      child: const Text(
                        "Clear Cache & Reset",
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                ],
                const SizedBox(height: 100),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(20),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final msg = _messages[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 15),
                    alignment: msg.isUser
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: msg.isUser
                            ? const Color(0xFF0EA5E9)
                            : const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(12),
                        border: msg.isUser
                            ? null
                            : Border.all(color: const Color(0xFF334155)),
                      ),
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.8,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (msg.imageBytes != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.memory(msg.imageBytes!),
                              ),
                            ),
                          if (msg.audioPath != null)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 8.0),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.audiotrack,
                                    size: 16,
                                    color: Colors.white70,
                                  ),
                                  Text(
                                    " [Audio recorded]",
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.white70,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          Text(
                            msg.text,
                            style: const TextStyle(
                              color: Colors.white,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Color(0xFF1E293B),
                border: Border(top: BorderSide(color: Color(0xFF334155))),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _MediaButton(
                        icon: Icons.camera_alt,
                        label: "Add Image",
                        onPressed: _pickImage,
                      ),
                      const SizedBox(width: 10),
                      FutureBuilder<bool>(
                        future: _audioRecorder.isRecording(),
                        builder: (context, snapshot) {
                          final isRec = snapshot.data ?? false;
                          return _MediaButton(
                            icon: isRec ? Icons.stop : Icons.mic,
                            label: isRec ? "Recording..." : "Record Audio",
                            onPressed: _toggleRecording,
                            color: isRec ? Colors.red : const Color(0xFF334155),
                          );
                        },
                      ),
                      const SizedBox(width: 10),
                      if (_selectedImageBytes != null ||
                          _recordedAudioPath != null)
                        Text(
                          _selectedImageBytes != null
                              ? "Image attached"
                              : "Audio recorded",
                          style: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: "Ask a question about the media...",
                            hintStyle: const TextStyle(
                              color: Color(0xFF94A3B8),
                            ),
                            filled: true,
                            fillColor: const Color(0xFF0F172A),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                color: Color(0xFF334155),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                color: Color(0xFF334155),
                              ),
                            ),
                          ),
                          onSubmitted: (_) => _handleChat(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _isSending
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : ElevatedButton(
                              onPressed: _handleChat,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0EA5E9),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 15,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: const Text(
                                "Send",
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ChatMessage {
  String text;
  final bool isUser;
  final Uint8List? imageBytes;
  final String? audioPath;

  ChatMessage({
    required this.text,
    required this.isUser,
    this.imageBytes,
    this.audioPath,
  });
}

class _MediaButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color color;

  const _MediaButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color = const Color(0xFF334155),
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: Colors.white),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
