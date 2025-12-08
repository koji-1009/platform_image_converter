import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_ffi/image_ffi.dart';
import 'package:image_picker/image_picker.dart';

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
  Uint8List? _originalImage;
  String? _originalName;
  Uint8List? _convertedImage;
  String? _convertedFormat;
  int? _convertElapsedMs;
  bool _isLoading = false;
  double _quality = 90;

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
      final converted = await ImageConverter.convert(
        inputData: _originalImage!,
        format: format,
        quality: _quality.round(),
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
      appBar: AppBar(title: const Text('image_ffi Demo')),
      body: SingleChildScrollView(
        padding: const .all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  Image.memory(_convertedImage!, height: 180),
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
