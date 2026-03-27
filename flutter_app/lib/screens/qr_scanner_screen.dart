import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';

class QRScannerScreen extends StatefulWidget {
  final String mode; // 'check_in' or 'check_out'
  const QRScannerScreen({super.key, required this.mode});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  MobileScannerController? _controller;
  bool _scanned = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_scanned) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode?.rawValue != null) {
      setState(() => _scanned = true);
      // Остановку камеры делаем без async-gap, чтобы избежать use_build_context_synchronously.
      _controller?.stop();
      context.pop(barcode!.rawValue);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCheckIn = widget.mode == 'check_in';
    final title = isCheckIn ? 'Сканирование прихода' : 'Сканирование ухода';
    final color = isCheckIn ? AppTheme.accent : AppTheme.error;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () async {
            await _controller?.stop();
            if (!context.mounted) return;
            context.pop();
          },
        ),
      ),
      body: Stack(
        children: [
          // Camera
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),

          // Overlay
          CustomPaint(
            painter: _ScannerOverlayPainter(color: color),
            child: const SizedBox.expand(),
          ),

          // Bottom instructions
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black.withOpacity(0.8), Colors.transparent],
                ),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: color.withOpacity(0.5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isCheckIn ? Icons.login_rounded : Icons.logout_rounded,
                          color: color, size: 18,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          isCheckIn ? 'Отметка прихода' : 'Отметка ухода',
                          style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Наведите камеру на QR-код',
                    style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14),
                  ),
                ],
              ),
            ),
          ),

          // Flash toggle
          Positioned(
            top: 20,
            right: 20,
            child: IconButton(
              icon: ValueListenableBuilder(
                valueListenable: _controller!.torchState,
                builder: (context, state, _) {
                  return Icon(
                    state == TorchState.on ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                    color: Colors.white,
                    size: 26,
                  );
                },
              ),
              onPressed: () => _controller?.toggleTorch(),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScannerOverlayPainter extends CustomPainter {
  final Color color;
  _ScannerOverlayPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withOpacity(0.55);
    const scanSize = 260.0;
    final centerX = size.width / 2;
    final centerY = size.height / 2 - 40;
    final rect = Rect.fromCenter(center: Offset(centerX, centerY), width: scanSize, height: scanSize);

    // Darken outside
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height)),
        Path()..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(20))),
      ),
      paint,
    );

    // Corner markers
    final cornerPaint = Paint()
      ..color = color
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const cornerLen = 30.0;
    final l = rect.left; final t = rect.top;
    final r = rect.right; final b = rect.bottom;
    const rad = 20.0;

    // Top-left
    canvas.drawLine(Offset(l + rad, t), Offset(l + rad + cornerLen, t), cornerPaint);
    canvas.drawLine(Offset(l, t + rad), Offset(l, t + rad + cornerLen), cornerPaint);
    // Top-right
    canvas.drawLine(Offset(r - rad, t), Offset(r - rad - cornerLen, t), cornerPaint);
    canvas.drawLine(Offset(r, t + rad), Offset(r, t + rad + cornerLen), cornerPaint);
    // Bottom-left
    canvas.drawLine(Offset(l + rad, b), Offset(l + rad + cornerLen, b), cornerPaint);
    canvas.drawLine(Offset(l, b - rad), Offset(l, b - rad - cornerLen), cornerPaint);
    // Bottom-right
    canvas.drawLine(Offset(r - rad, b), Offset(r - rad - cornerLen, b), cornerPaint);
    canvas.drawLine(Offset(r, b - rad), Offset(r, b - rad - cornerLen), cornerPaint);
  }

  @override
  bool shouldRepaint(_) => false;
}
