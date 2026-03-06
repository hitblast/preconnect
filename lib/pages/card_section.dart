import 'dart:io';
import 'dart:math' as math;

import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:preconnect/tools/cached_image.dart';

const String _bracuLogoUrl = 'https://cse.sds.bracu.ac.bd/img/logo.png';

class CardSection extends StatefulWidget {
  const CardSection({
    super.key,
    required this.profile,
    required this.photoUrl,
    this.cachedImageFile,
  });

  final Map<String, String?>? profile;
  final String? photoUrl;
  final File? cachedImageFile;

  @override
  State<CardSection> createState() => _CardSectionState();
}

class _CardSectionState extends State<CardSection> {
  bool _showBack = false;
  Axis _flipAxis = Axis.horizontal;
  double _flipDirection = 1;

  void _toggleCard({
    Axis axis = Axis.horizontal,
    double direction = 1,
  }) {
    setState(() {
      _flipAxis = axis;
      _flipDirection = direction == 0 ? 1 : direction.sign;
      _showBack = !_showBack;
    });
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile ?? {};
    final fullName = (profile['fullName'] ?? '').trim();
    final degreeName = (profile['program'] ?? '').trim();
    final studentId = (profile['studentId'] ?? '').trim();
    final enrolledSession = int.tryParse(
      (profile['enrolledSessionSemesterId'] ?? '').trim(),
    );
    final validation = enrolledSession == null
        ? ''
        : '31-12-${(enrolledSession ~/ 10) + 5}';
    final bloodGroup = (profile['bloodGroup'] ?? '').trim();
    final photoUrl = widget.photoUrl;
    final displayName = fullName.isNotEmpty ? fullName : 'BRACU Student';
    final displayProgram = degreeName.isNotEmpty ? degreeName : '';
    final displayStudentId = studentId.isNotEmpty ? studentId : '';
    final displayBloodGroup = bloodGroup.isNotEmpty ? bloodGroup : '--';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _toggleCard(),
          onDoubleTap: () => _toggleCard(),
          onPanEnd: (details) {
            final dx = details.velocity.pixelsPerSecond.dx;
            final dy = details.velocity.pixelsPerSecond.dy;
            final absDx = dx.abs();
            final absDy = dy.abs();
            const minVelocity = 40.0;
            if (absDx < minVelocity && absDy < minVelocity) return;
            if (absDx >= absDy) {
              _toggleCard(
                axis: Axis.horizontal,
                direction: dx >= 0 ? 1 : -1,
              );
              return;
            }
            _toggleCard(
              axis: Axis.vertical,
              direction: dy >= 0 ? 1 : -1,
            );
          },
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 380),
            switchInCurve: Curves.easeInOutCubic,
            switchOutCurve: Curves.easeInOutCubic,
            layoutBuilder: (currentChild, previousChildren) {
              return Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  ...previousChildren,
                  ...(currentChild == null ? const <Widget>[] : <Widget>[currentChild]),
                ],
              );
            },
            transitionBuilder: (child, animation) {
              final rotation = Tween<double>(
                begin: math.pi / 2,
                end: 0,
              ).animate(animation);
              return AnimatedBuilder(
                animation: rotation,
                child: child,
                builder: (context, builtChild) {
                  return Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.0015)
                      ..rotateY(
                        _flipAxis == Axis.horizontal
                            ? rotation.value * _flipDirection
                            : 0,
                      )
                      ..rotateX(
                        _flipAxis == Axis.vertical
                            ? rotation.value * _flipDirection
                            : 0,
                      ),
                    child: builtChild,
                  );
                },
              );
            },
            child: _showBack
                ? _CardBack(
                    key: const ValueKey<String>('card-back'),
                    displayStudentId: displayStudentId,
                  )
                : _CardFront(
                    key: const ValueKey<String>('card-front'),
                    displayName: displayName,
                    displayProgram: displayProgram,
                    displayStudentId: displayStudentId,
                    displayBloodGroup: displayBloodGroup,
                    validation: validation,
                    photoUrl: photoUrl,
                  ),
          ),
        ),
      ],
    );
  }
}

class _CardFront extends StatelessWidget {
  const _CardFront({
    super.key,
    required this.displayName,
    required this.displayProgram,
    required this.displayStudentId,
    required this.displayBloodGroup,
    required this.validation,
    required this.photoUrl,
  });

  final String displayName;
  final String displayProgram;
  final String displayStudentId;
  final String displayBloodGroup;
  final String validation;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black),
          boxShadow: const [
            BoxShadow(
              color: Color.fromRGBO(0, 0, 0, 0.18),
              offset: Offset(0, 4),
              blurRadius: 6,
            ),
          ],
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
              child: Row(
                children: [
                  const _BracuLogo(width: 34, height: 34),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'BRAC University',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 21,
                          color: Colors.black,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(
              color: Colors.black,
              thickness: 0.9,
              height: 0,
              indent: 0,
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 138),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(16),
                      ),
                    ),
                    child: const RotatedBox(
                      quarterTurns: 3,
                      child: Text(
                        'STUDENT',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 18,
                          letterSpacing: 1.4,
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      decoration: const BoxDecoration(
                        color: Color(0xFF7BB3D3),
                        borderRadius: BorderRadius.only(
                          bottomRight: Radius.circular(16),
                        ),
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          const Opacity(
                            opacity: 0.06,
                            child: _BracuLogo(width: 120, height: 120),
                          ),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                flex: 6,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      displayName,
                                      style: const TextStyle(
                                        color: Colors.black,
                                        fontSize: 13,
                                        fontFamily: 'Poppins',
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      displayProgram,
                                      style: const TextStyle(
                                        color: Colors.black,
                                        fontSize: 9,
                                        fontFamily: 'Poppins',
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    _InfoRow(
                                      label: 'Student ID',
                                      value: displayStudentId,
                                      enableCopy: true,
                                    ),
                                    const SizedBox(height: 5),
                                    _InfoRow(
                                      label: 'Blood Group',
                                      value: displayBloodGroup,
                                    ),
                                    const SizedBox(height: 5),
                                    _InfoRow(
                                      label: 'Validity',
                                      value: validation,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              SizedBox(
                                width: 90,
                                height: 106,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: photoUrl == null || photoUrl!.isEmpty
                                      ? const SizedBox.expand()
                                      : CachedImage(
                                          url: photoUrl!,
                                          fit: BoxFit.cover,
                                          alignment: Alignment.center,
                                          placeholder: const SizedBox.expand(),
                                          error: const SizedBox.expand(),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
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

class _CardBack extends StatelessWidget {
  const _CardBack({
    super.key,
    required this.displayStudentId,
  });

  final String displayStudentId;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black),
        color: const Color(0xFF67ADD8),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.25),
            offset: Offset(0, 4),
            blurRadius: 4,
          ),
        ],
      ),
      width: double.infinity,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Opacity(
            opacity: 0.1,
            child: _BracuLogo(width: 140, height: 120),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(48, 24, 2, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Unauthorized ID card of BRACU. Generated by PreConnect App.',
                  style: TextStyle(
                    fontSize: 8,
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Do not accept this card as a valid ID without the original physical card.',
                  style: TextStyle(
                    fontSize: 8,
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Contact:',
                  style: TextStyle(
                    fontSize: 8,
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'BRAC University\n'
                  'Kha 224 Bir Uttam Rafiqul Islam Ave,\n'
                  'Merul Badda, Dhaka 1212, Bangladesh',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 7,
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Tel : +8809638464646 ext. 1653\n'
                  'Email : idcard@bracu.ac.bd',
                  style: TextStyle(
                    fontSize: 9,
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
                Row(
                  children: [
                    const Expanded(flex: 4, child: Text('')),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: BarcodeWidget(
                        barcode: Barcode.code128(),
                        data: displayStudentId,
                        width: 100,
                        height: 10,
                        drawText: false,
                        backgroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
                Container(
                  width: 80,
                  height: 1,
                  color: const Color(0xFF1E1E1E),
                ),
                const Text(
                  'Authorized Signature',
                  style: TextStyle(
                    fontSize: 7,
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.enableCopy = false,
  });

  final String label;
  final String value;
  final bool enableCopy;

  @override
  Widget build(BuildContext context) {
    const textStyle = TextStyle(
      color: Colors.black,
      fontSize: 9,
      fontFamily: 'Poppins',
      fontWeight: FontWeight.w700,
    );
    return Row(
      children: [
        SizedBox(width: 74, child: Text(label, style: textStyle)),
        const Text(':', style: textStyle),
        const SizedBox(width: 8),
        Expanded(
          child: enableCopy
              ? GestureDetector(
                  onTap: () => copyToClipboard(context, value),
                  child: Text(value, style: textStyle),
                )
              : Text(value, style: textStyle),
        ),
      ],
    );
  }
}

class _BracuLogo extends StatelessWidget {
  const _BracuLogo({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      _bracuLogoUrl,
      width: width,
      height: height,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => SizedBox(width: width, height: height),
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return SizedBox(width: width, height: height);
      },
    );
  }
}
