import 'dart:async' show Completer;
import 'dart:math' show max, min, exp;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'perfil_screen.dart';
import 'registros_screen.dart';

// ── Preprocessing (runs in isolate via compute()) ─────────────────────────────

Map<String, dynamic> _prepareInputTensor(Map<String, dynamic> a) {
  final int w = a['w'] as int, h = a['h'] as int, m = a['m'] as int;
  final Uint8List yB = a['y'] as Uint8List;
  final Uint8List uB = a['u'] as Uint8List;
  final Uint8List vB = a['v'] as Uint8List;
  final int yS = a['yS'] as int;
  final int uvRS = a['uvRS'] as int;
  final int uvPS = a['uvPS'] as int;

  final rgb = img.Image(width: w, height: h);
  for (int row = 0; row < h; row++) {
    for (int col = 0; col < w; col++) {
      final uvIdx = uvPS * (col ~/ 2) + uvRS * (row ~/ 2);
      final yp = yB[row * yS + col] & 0xFF;
      final up = uB[uvIdx] & 0xFF;
      final vp = vB[uvIdx] & 0xFF;
      final r = (yp + (vp - 128) * 1.402).clamp(0, 255).toInt();
      final g = (yp - (up - 128) * 0.344136 - (vp - 128) * 0.714136)
          .clamp(0, 255)
          .toInt();
      final b = (yp + (up - 128) * 1.772).clamp(0, 255).toInt();
      rgb.setPixelRgba(col, row, r, g, b, 255);
    }
  }

  // Mapear orientación del sensor al ángulo real que necesita img.copyRotate
  final int sensorRot = a['rot'] as int;
  int rotAngle = 0;
  if (sensorRot == 90) {
    rotAngle = 90;
  } else if (sensorRot == 180) {
    rotAngle = 180;
  } else if (sensorRot == 270) {
    rotAngle = -90;
  }

  final img.Image upright = rotAngle == 0
      ? rgb
      : img.copyRotate(rgb, angle: rotAngle.toDouble());
  final int fw = upright.width;
  final int fh = upright.height;

  // Letterbox: same gray padding as YOLOv8 training (114,114,114)
  final double scale = min(m / fw, m / fh);
  final int newW = (fw * scale).round();
  final int newH = (fh * scale).round();
  final int padX = (m - newW) ~/ 2;
  final int padY = (m - newH) ~/ 2;

  final resized = img.copyResize(upright, width: newW, height: newH);
  final canvas = img.Image(width: m, height: m);
  img.fill(canvas, color: img.ColorRgb8(114, 114, 114));
  img.compositeImage(canvas, resized, dstX: padX, dstY: padY);

  final tensor = Float32List(m * m * 3);
  int idx = 0;
  for (int y = 0; y < m; y++) {
    for (int x = 0; x < m; x++) {
      final p = canvas.getPixel(x, y);
      tensor[idx++] = p.r.toDouble() / 255.0;
      tensor[idx++] = p.g.toDouble() / 255.0;
      tensor[idx++] = p.b.toDouble() / 255.0;
    }
  }
  final jpeg = img.encodeJpg(upright, quality: 80);
  return {
    'tensor': tensor,
    'jpeg': jpeg,
    'padX': padX,
    'padY': padY,
    'scale': scale,
    'frameW': fw,
    'frameH': fh,
  };
}

// ── Data models ───────────────────────────────────────────────────────────────

class SegmentDetection {
  final double x1, y1, x2, y2, confidence;
  final ui.Image? maskImg;

  SegmentDetection({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.confidence,
    this.maskImg,
  });
}

class _RawSegDetection {
  final double x1, y1, x2, y2, confidence;
  final List<double> maskCoeffs;

  _RawSegDetection({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.confidence,
    required this.maskCoeffs,
  });
}

// ── Painter for segmentation masks ────────────────────────────────────────────

class SegmentationPainter extends CustomPainter {
  final List<SegmentDetection> detections;
  final double padX, padY, scale;
  final int frameW, frameH;

  SegmentationPainter({
    required this.detections,
    required this.padX,
    required this.padY,
    required this.scale,
    required this.frameW,
    required this.frameH,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // The 160×160 mask covers the full 640×640 letterboxed space.
    // srcRect picks out only the portion that maps to the real camera frame.
    final srcRect = Rect.fromLTWH(
      padX / 4.0,
      padY / 4.0,
      frameW * scale / 4.0,
      frameH * scale / 4.0,
    );
    final dstRect = Rect.fromLTWH(0, 0, size.width, size.height);

    final bboxPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final scaleX = frameW > 0 ? size.width / frameW : 1.0;
    final scaleY = frameH > 0 ? size.height / frameH : 1.0;

    for (final det in detections) {
      final bboxRect = Rect.fromLTRB(
        det.x1 * scaleX,
        det.y1 * scaleY,
        det.x2 * scaleX,
        det.y2 * scaleY,
      );

      if (det.maskImg != null) {
        // Recortar la máscara al área del bounding box para que no se salga
        canvas.save();
        canvas.clipRect(bboxRect);
        canvas.drawImageRect(det.maskImg!, srcRect, dstRect, Paint());
        canvas.restore();
      }

      canvas.drawRect(bboxRect, bboxPaint);
    }
  }

  @override
  bool shouldRepaint(SegmentationPainter old) => old.detections != detections;
}

// ── Main screen ───────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  final String maquinaId;
  final String maquinaNombre;
  final String usuarioId;
  final String usuarioNombre;

  const HomeScreen({
    super.key,
    this.maquinaId = '',
    this.maquinaNombre = 'Bavaria IA',
    this.usuarioId = '',
    this.usuarioNombre = '',
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _kModelInput = 640;
  static const _kDetFreq = 20;
  static const _kPurple = Color(0xFF663399);
  static const _kLightPurple = Color(0xFFF2EBFA);

  final _supabase = Supabase.instance.client;
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  CameraController? _cam;
  Interpreter? _interpreter;
  List<int>? _outputShape;
  List<int>? _outputShape1;

  bool _cameraActive = false;
  bool _isProcessing = false;
  List<SegmentDetection> _detections = [];
  int _frameCount = 0;
  Size _camFrameSize = const Size(640, 480);
  int _sensorOrientation = 90;
  double _maxConfSeen = 0;
  int _inferenceCount = 0;
  List<int>? _inputShape;

  double _letterPadX = 0;
  double _letterPadY = 0;
  double _letterScale = 1;
  Uint8List? _capturedPhotoBytes;

  @override
  void initState() {
    super.initState();
    _init();
  }

  // ── Initialization ────────────────────────────────────────────────────────

  Future<void> _init() async {
    await _requestPermissions();
    await _loadModel();
  }

  Future<void> _requestPermissions() async {
    await Permission.camera.request();
    await Permission.storage.request();
  }

  Future<void> _loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset(
        'assets/models/buenito1.tflite',
      );
      final inShape = _interpreter!.getInputTensor(0).shape;
      final outShape0 = _interpreter!.getOutputTensor(0).shape;
      _outputShape = outShape0;
      _inputShape = inShape;

      // Seg models have a second output tensor (prototypes [1,32,160,160])
      final inputType = _interpreter!.getInputTensor(0).type;
      debugPrint('Input type: $inputType');

      try {
        final outShape1 = _interpreter!.getOutputTensor(1).shape;
        _outputShape1 = outShape1;
        debugPrint(
          'TFLite Seg — input: $inShape  out0: $outShape0  out1: $outShape1',
        );
      } catch (_) {
        _outputShape1 = null;
        debugPrint('TFLite Det — input: $inShape  out0: $outShape0');
      }

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Error cargando modelo: $e');
    }
  }

  // ── Camera control ────────────────────────────────────────────────────────

  Future<void> _toggleCamera() async {
    if (!_cameraActive) {
      await _startCamera();
    } else {
      await _stopCamera();
    }
  }

  Future<void> _startCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;
      _cam = CameraController(
        cameras[0],
        ResolutionPreset.low,
        imageFormatGroup: ImageFormatGroup.yuv420,
        enableAudio: false,
      );
      await _cam!.initialize();
      if (!mounted) return;
      final sensorOrientation = cameras[0].sensorOrientation;
      setState(() {
        _cameraActive = true;
        _sensorOrientation = sensorOrientation;
      });
      _cam!.startImageStream(_onFrame);
    } catch (e) {
      debugPrint('Error iniciando cámara: $e');
    }
  }

  Future<void> _stopCamera() async {
    try {
      await _cam?.stopImageStream();
      await _cam?.dispose();
      _cam = null;
    } catch (e) {
      debugPrint('Error deteniendo cámara: $e');
    }
    if (mounted) {
      setState(() {
        _cameraActive = false;
        for (final det in _detections) {
          det.maskImg?.dispose();
        }
        _detections = [];
      });
    }
  }

  // ── Inference pipeline ────────────────────────────────────────────────────

  void _onFrame(CameraImage frame) {
    _frameCount++;
    if (_frameCount < _kDetFreq || _isProcessing || _interpreter == null) {
      return;
    }
    _frameCount = 0;
    _isProcessing = true;
    _runInference(frame).whenComplete(() => _isProcessing = false);
  }

  Future<void> _runInference(CameraImage cameraImage) async {
    try {
      if (_outputShape == null || _interpreter == null) return;
      if (cameraImage.format.group != ImageFormatGroup.yuv420) return;

      final prepared = await compute(_prepareInputTensor, {
        'w': cameraImage.width,
        'h': cameraImage.height,
        'y': cameraImage.planes[0].bytes,
        'u': cameraImage.planes[1].bytes,
        'v': cameraImage.planes[2].bytes,
        'yS': cameraImage.planes[0].bytesPerRow,
        'uvRS': cameraImage.planes[1].bytesPerRow,
        'uvPS': cameraImage.planes[1].bytesPerPixel!,
        'm': _kModelInput,
        'rot': _sensorOrientation,
      });

      final tensor = prepared['tensor'] as Float32List;
      final padX = (prepared['padX'] as int).toDouble();
      final padY = (prepared['padY'] as int).toDouble();
      final scale = prepared['scale'] as double;
      final frameW = prepared['frameW'] as int;
      final frameH = prepared['frameH'] as int;

      final input = tensor.reshape([1, _kModelInput, _kModelInput, 3]);
      final s0 = _outputShape!;

      // Allocate output tensors
      final out0 = [
        List.generate(s0[1], (_) => List<double>.filled(s0[2], 0.0)),
      ];

      List? out1;
      if (_outputShape1 != null) {
        final s1 = _outputShape1!;
        out1 = [
          List.generate(
            s1[1],
            (_) => List.generate(s1[2], (_) => List<double>.filled(s1[3], 0.0)),
          ),
        ];
        _interpreter!.runForMultipleInputs([input], {0: out0, 1: out1});
      } else {
        _interpreter!.run(input, out0);
      }

      // Transpose if model uses [1, numVals, numDets] layout (s0[1] < s0[2])
      List<List<double>> rows;
      if (s0[1] < s0[2]) {
        final numVals = s0[1], numDets = s0[2];
        rows = List.generate(
          numDets,
          (i) =>
              List.generate(numVals, (j) => (out0[0][j] as List)[i] as double),
        );
      } else {
        rows = (out0[0] as List)
            .map((r) => List<double>.from(r as List))
            .toList();
      }

      final rawDets = _parseSegOutput(rows);

      // Build mask images for each surviving detection
      final List<SegmentDetection> dets = [];
      for (final raw in rawDets) {
        final cx1 = ((raw.x1 - padX) / scale).clamp(0.0, frameW.toDouble());
        final cy1 = ((raw.y1 - padY) / scale).clamp(0.0, frameH.toDouble());
        final cx2 = ((raw.x2 - padX) / scale).clamp(0.0, frameW.toDouble());
        final cy2 = ((raw.y2 - padY) / scale).clamp(0.0, frameH.toDouble());

        ui.Image? maskImg;
        if (out1 != null && raw.maskCoeffs.isNotEmpty) {
          final rgba = _buildMaskRgba(raw.maskCoeffs, out1[0] as List);
          maskImg = await _rgbaToImage(rgba, 160, 160);
        }

        dets.add(
          SegmentDetection(
            x1: cx1,
            y1: cy1,
            x2: cx2,
            y2: cy2,
            confidence: raw.confidence,
            maskImg: maskImg,
          ),
        );
      }

      // Release previous mask GPU textures
      for (final old in _detections) {
        old.maskImg?.dispose();
      }

      if (mounted) {
        setState(() {
          _detections = dets;
          _camFrameSize = Size(frameW.toDouble(), frameH.toDouble());
          _letterPadX = padX;
          _letterPadY = padY;
          _letterScale = scale;
          _inferenceCount++;
          if (dets.isNotEmpty) {
            _capturedPhotoBytes = prepared['jpeg'] as Uint8List?;
          }
        });
      }
    } catch (e) {
      debugPrint('Inference error: $e');
    }
  }

  List<_RawSegDetection> _parseSegOutput(List<List<double>> rows) {
    final result = <_RawSegDetection>[];
    double localMax = 0;
    final modelW = _kModelInput.toDouble();
    const numMaskCoeffs = 32;

    for (final row in rows) {
      // Need at least 4 (bbox) + 1 (class score)
      if (row.length < 5) continue;

      // Seg model: row.length = 4 + numClasses + 32  (e.g. 37 for 1 class)
      // Det model: row.length = 4 + numClasses        (e.g.  5 for 1 class)
      final bool isSeg = row.length > 36;
      final int maskStart = isSeg ? row.length - numMaskCoeffs : row.length;

      // Max class score (indices 4 .. maskStart-1)
      double conf = 0;
      for (int i = 4; i < maskStart; i++) {
        if (row[i] > conf) conf = row[i];
      }
      if (conf > localMax) localMax = conf;
      if (conf < 0.40) continue;

      final cx = row[0], cy = row[1], bw = row[2], bh = row[3];
      double x1, y1, x2, y2;

      if (cx <= 1.01 && cy <= 1.01) {
        x1 = (cx - bw / 2) * modelW;
        y1 = (cy - bh / 2) * modelW;
        x2 = (cx + bw / 2) * modelW;
        y2 = (cy + bh / 2) * modelW;
      } else {
        x1 = cx - bw / 2;
        y1 = cy - bh / 2;
        x2 = cx + bw / 2;
        y2 = cy + bh / 2;
      }

      result.add(
        _RawSegDetection(
          x1: x1.clamp(0, modelW),
          y1: y1.clamp(0, modelW),
          x2: x2.clamp(0, modelW),
          y2: y2.clamp(0, modelW),
          confidence: conf,
          maskCoeffs: isSeg ? row.sublist(maskStart) : [],
        ),
      );
    }
    _maxConfSeen = localMax;
    return _nmsRaw(result, 0.45);
  }

  List<_RawSegDetection> _nmsRaw(
    List<_RawSegDetection> dets,
    double threshold,
  ) {
    final sorted = [...dets]
      ..sort((a, b) => b.confidence.compareTo(a.confidence));
    final keep = <_RawSegDetection>[];
    for (final det in sorted) {
      bool suppress = false;
      for (final kept in keep) {
        if (_iouRaw(det, kept) > threshold) {
          suppress = true;
          break;
        }
      }
      if (!suppress) keep.add(det);
    }
    return keep;
  }

  double _iouRaw(_RawSegDetection a, _RawSegDetection b) {
    final ix1 = max(a.x1, b.x1);
    final iy1 = max(a.y1, b.y1);
    final ix2 = min(a.x2, b.x2);
    final iy2 = min(a.y2, b.y2);
    final inter = max(0.0, ix2 - ix1) * max(0.0, iy2 - iy1);
    final aArea = (a.x2 - a.x1) * (a.y2 - a.y1);
    final bArea = (b.x2 - b.x1) * (b.y2 - b.y1);
    return inter / (aArea + bArea - inter + 1e-8);
  }

  // Computes sigmoid(coeffs · protos) → RGBA Uint8List (160×160, red overlay)
  // out1 shape es [1, 160, 160, 32] → protos[y][x][k]
  Uint8List _buildMaskRgba(List<double> coeffs, List protos) {
    const int maskSize = 160;
    final rgba = Uint8List(maskSize * maskSize * 4);
    for (int y = 0; y < maskSize; y++) {
      final protoY = protos[y] as List;
      for (int x = 0; x < maskSize; x++) {
        final protoYX = protoY[x] as List;
        double val = 0;
        for (int k = 0; k < coeffs.length; k++) {
          val += coeffs[k] * (protoYX[k] as num).toDouble();
        }
        final maskVal = 1.0 / (1.0 + exp(-val));
        if (maskVal > 0.6) {
          final i = (y * maskSize + x) * 4;
          rgba[i] = 255;
          rgba[i + 1] = 0;
          rgba[i + 2] = 0;
          rgba[i + 3] = 180;
        }
      }
    }
    return rgba;
  }

  Future<ui.Image> _rgbaToImage(Uint8List rgba, int w, int h) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      w,
      h,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  // ── Guardar reporte ───────────────────────────────────────────────────────

  Future<void> _saveReport() async {
    if (_detections.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay rayones detectados actualmente')),
      );
      return;
    }

    final obsController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Guardar reporte'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Máquina: ${widget.maquinaNombre}'),
            Text('OPM: ${widget.usuarioNombre}'),
            Text('Rayones: ${_detections.length}   Confianza: ${(_maxConfSeen * 100).toStringAsFixed(0)}%'),
            const SizedBox(height: 12),
            TextField(
              controller: obsController,
              decoration: const InputDecoration(
                labelText: 'Observaciones (opcional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _kPurple, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      obsController.dispose();
      return;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Guardando reporte...')),
      );
    }

    try {
      // Subir foto capturada durante la última inferencia (sin pausar cámara)
      String? photoUrl;
      final photoBytes = _capturedPhotoBytes;
      if (photoBytes != null) {
        try {
          final path =
              '${widget.maquinaId}_${widget.usuarioId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
          await _supabase.storage
              .from('fotos-rayones')
              .uploadBinary(
                path,
                photoBytes,
                fileOptions: const FileOptions(contentType: 'image/jpeg'),
              );
          photoUrl =
              _supabase.storage.from('fotos-rayones').getPublicUrl(path);
        } catch (e) {
          debugPrint('Error subiendo foto: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Foto no guardada: $e'),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 6),
              ),
            );
          }
        }
      }

      await _supabase.from('reporte').insert({
        'maquina_id': int.tryParse(widget.maquinaId),
        'usuario_id': int.tryParse(widget.usuarioId),
        'foto_rayon_url': photoUrl,
        'confianza': _maxConfSeen,
        'cantidad_rayones': _detections.length,
        'fecha_hora': DateTime.now().toIso8601String(),
        'observaciones': obsController.text.trim().isEmpty
            ? null
            : obsController.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reporte guardado'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al guardar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      obsController.dispose();
    }
  }

  // ── Drawer ────────────────────────────────────────────────────────────────

  Widget _buildDrawer() {
    return Drawer(
      child: Column(
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(color: _kLightPurple),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Icon(Icons.person_outline, color: _kPurple, size: 40),
                const SizedBox(height: 6),
                Text(
                  widget.usuarioNombre.isEmpty ? 'OPM' : widget.usuarioNombre,
                  style: const TextStyle(
                    color: _kPurple,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Máquina: ${widget.maquinaNombre}',
                  style: const TextStyle(color: _kPurple, fontSize: 12),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.person, color: _kPurple),
            title: const Text('Perfil'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PerfilScreen(
                    usuarioId: widget.usuarioId,
                    usuarioNombre: widget.usuarioNombre,
                  ),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo_library, color: _kPurple),
            title: const Text('Registros'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => RegistrosScreen(
                    maquinaId: widget.maquinaId,
                    maquinaNombre: widget.maquinaNombre,
                  ),
                ),
              );
            },
          ),
          const Spacer(),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Cerrar Sesión',
                style: TextStyle(color: Colors.red)),
            onTap: () {
              Navigator.pop(context);
              _stopCamera().then((_) {
                if (mounted) Navigator.pushReplacementNamed(context, '/login');
              });
            },
          ),
        ],
      ),
    );
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _cam?.stopImageStream();
    _cam?.dispose();
    _cam = null;
    _interpreter?.close();
    for (final det in _detections) {
      det.maskImg?.dispose();
    }
    super.dispose();
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildDrawer(),
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              height: 60,
              color: _kLightPurple,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.menu, color: _kPurple, size: 32),
                    onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                  ),
                  Expanded(
                    child: Text(
                      widget.maquinaNombre,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: _kPurple,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 50),
                ],
              ),
            ),
            Expanded(flex: 7, child: _buildCameraArea()),
            Expanded(
              flex: 2,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 200,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _toggleCamera,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _cameraActive
                            ? const Color(0xFFCC0000)
                            : _kPurple,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        _cameraActive ? 'DETENER' : 'INICIAR DETECCIÓN',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  if (_cameraActive && _detections.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    SizedBox(
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: _saveReport,
                        icon: const Icon(Icons.save_alt),
                        label: const Text('Guardar'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Spacer(flex: 1),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraArea() {
    if (!_cameraActive || _cam == null || !_cam!.value.isInitialized) {
      return Container(
        color: Colors.black12,
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.camera_alt_outlined, size: 64, color: Colors.grey),
              SizedBox(height: 12),
              Text(
                'Presiona INICIAR DETECCIÓN\npara activar la cámara',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          fit: StackFit.expand,
          children: [
            CameraPreview(_cam!),
            if (_detections.isNotEmpty)
              CustomPaint(
                painter: SegmentationPainter(
                  detections: _detections,
                  padX: _letterPadX,
                  padY: _letterPadY,
                  scale: _letterScale,
                  frameW: _camFrameSize.width.toInt(),
                  frameH: _camFrameSize.height.toInt(),
                ),
              ),
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                color: Colors.black54,
                child: Text(
                  'In: $_inputShape\nOut0: $_outputShape  Out1: $_outputShape1\n'
                  '#$_inferenceCount  Segs:${_detections.length}  MaxConf:${_maxConfSeen.toStringAsFixed(3)}',
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

