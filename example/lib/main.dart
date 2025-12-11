import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:platform_image_converter/platform_image_converter.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Image FFI Demo',
      theme: ThemeData.light(),
      home: MainPage(),
    );
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  final _widthController = TextEditingController();
  final _heightController = TextEditingController();

  Uint8List? _originalImage;
  String? _originalName;
  Uint8List? _convertedImage;
  String? _convertedFormat;
  int? _convertElapsedMs;
  bool _isLoading = false;
  double _quality = 90;

  @override
  void dispose() {
    _widthController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      _originalImage = await pickedFile.readAsBytes();
      _originalName = pickedFile.name;
      _convertedImage = null;
      _convertedFormat = null;
      _convertElapsedMs = null;
      setState(() {});
    }
  }

  Future<void> _convertImage(OutputFormat format) async {
    if (_originalImage == null) return;
    setState(() => _isLoading = true);
    final sw = Stopwatch()..start();
    try {
      final width = int.tryParse(_widthController.text);
      final height = int.tryParse(_heightController.text);
      final resizeMode = switch ((width, height)) {
        (null, null) => const OriginalResizeMode(),
        (final w?, final h?) => ExactResizeMode(width: w, height: h),
        (final w?, null) => FitResizeMode(width: w, height: 1 << 30),
        (null, final h?) => FitResizeMode(width: 1 << 30, height: h),
      };

      final converted = await ImageConverter.convert(
        inputData: _originalImage!,
        format: format,
        quality: _quality.round(),
        resizeMode: resizeMode,
      );
      sw.stop();
      _convertedImage = converted;
      _convertedFormat = format.name;
      _convertElapsedMs = sw.elapsedMilliseconds;
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Conversion failed: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('platform_image_converter Demo')),
      body: SingleChildScrollView(
        padding: const .all(16),
        keyboardDismissBehavior: .onDrag,
        child: Column(
          crossAxisAlignment: .stretch,
          children: [
            FilledButton(
              onPressed: _pickImage,
              child: const Text('Pick Image'),
            ),
            const SizedBox(height: 8),
            Text('Quality: ${_quality.round()}%'),
            Slider(
              value: _quality,
              min: 1,
              max: 100,
              divisions: 99,
              label: _quality.round().toString(),
              onChanged: _isLoading
                  ? null
                  : (v) => setState(() => _quality = v),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _widthController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Width',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _heightController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Height',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            if (_originalImage != null) ...[
              Text('Original Image ($_originalName): '),
              Image.memory(_originalImage!, height: 180),
              const SizedBox(height: 8),
              Row(
                spacing: 4,
                children: [
                  ActionChip(
                    onPressed: _isLoading
                        ? null
                        : () => _convertImage(OutputFormat.jpeg),
                    label: const Text('to JPG'),
                  ),
                  ActionChip(
                    onPressed: _isLoading
                        ? null
                        : () => _convertImage(OutputFormat.png),
                    label: const Text('to PNG'),
                  ),
                  ActionChip(
                    onPressed: _isLoading
                        ? null
                        : () => _convertImage(OutputFormat.webp),
                    label: const Text('to WebP'),
                  ),
                  ActionChip(
                    onPressed: _isLoading
                        ? null
                        : () => _convertImage(OutputFormat.heic),
                    label: const Text('to HEIC'),
                  ),
                ],
              ),
            ],
            if (_isLoading)
              const Padding(
                padding: .all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (!_isLoading && _convertedImage != null)
              Column(
                children: [
                  Text('Converted ($_convertedFormat):'),
                  Image.memory(_convertedImage!, height: 180, fit: .contain),
                  Text('Size: ${_convertedImage!.lengthInBytes} bytes'),
                  if (_convertElapsedMs != null)
                    Text('Convert time: $_convertElapsedMs ms'),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
