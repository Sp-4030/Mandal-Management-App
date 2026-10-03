import 'dart:io';

import 'package:flutter/material.dart';

import '../services/update_service.dart';

class AppUpdateScreen extends StatefulWidget {
  final bool isMandatory;
  final UpdateCheckResult? initialCheckResult;

  const AppUpdateScreen({
    super.key,
    this.isMandatory = false,
    this.initialCheckResult,
  });

  @override
  State<AppUpdateScreen> createState() => _AppUpdateScreenState();
}

class _AppUpdateScreenState extends State<AppUpdateScreen>
    with WidgetsBindingObserver {
  final UpdateService _updateService = UpdateService();

  String _currentVersion = '1.0.0';
  bool _isLoadingVersion = true;
  bool _isChecking = false;
  bool _isDownloading = false;

  double _downloadProgress = 0.0;
  int _downloadedBytes = 0;
  int _totalBytes = 0;
  UpdateCancelToken? _cancelToken;
  File? _downloadedApkFile;

  UpdateCheckResult? _checkResult;
  String? _statusMessage;
  String? _errorMessage;

  UpdateInfo? _pendingUpdateInfo;
  DateTime? _lastCheckedTime;

  static const Color _saffron = Color(0xFFFF7A00);
  static const Color _deepSaffron = Color(0xFFB94D00);
  static const Color _warmPaper = Color(0xFFFFFAF3);
  static const Color _ink = Color(0xFF25231F);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.initialCheckResult != null) {
      _checkResult = widget.initialCheckResult;
      _currentVersion = widget.initialCheckResult!.currentVersion;
      _isLoadingVersion = false;
      _lastCheckedTime = DateTime.now();
      if (widget.initialCheckResult!.status ==
          UpdateCheckStatus.updateAvailable) {
        _statusMessage = 'नवीन अपडेट उपलब्ध आहे';
      }
    } else {
      _loadCurrentVersion();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelToken?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _handleAppResumed();
    }
  }

  /// Called when user returns to app from Android settings.
  /// Re-checks permission and continues installation automatically if granted.
  Future<void> _handleAppResumed() async {
    final hasPermission = await _updateService.canInstallPackages();
    if (hasPermission) {
      // Permission is now granted!
      if (_downloadedApkFile != null && await _downloadedApkFile!.exists()) {
        // APK already downloaded, directly launch installer
        await _launchInstaller(_downloadedApkFile!.path);
      } else if (_pendingUpdateInfo != null) {
        // Automatically continue download and APK installation
        final info = _pendingUpdateInfo!;
        _pendingUpdateInfo = null;
        if (mounted) {
          setState(() {
            _errorMessage = null;
          });
        }
        await _startUpdateDownload(info);
      }
    } else {
      // Permission still denied
      if (_pendingUpdateInfo != null) {
        _pendingUpdateInfo = null;
        if (mounted) {
          setState(() {
            _errorMessage =
                'अज्ञात अॅप्स इन्स्टॉल करण्याची परवानगी आवश्यक आहे.\nकृपया सेटिंग्जमध्ये जाऊन परवानगी सुरू करा.';
          });
        }
      }
    }
  }

  Future<void> _loadCurrentVersion() async {
    try {
      final version = await _updateService.getCurrentVersion();
      if (mounted) {
        setState(() {
          _currentVersion = version;
          _isLoadingVersion = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingVersion = false;
        });
      }
    }
  }

  Future<void> _checkForUpdate() async {
    if (_isChecking || _isDownloading) return;

    setState(() {
      _isChecking = true;
      _errorMessage = null;
      _statusMessage = 'तपासत आहे... (Checking...)';
      _checkResult = null;
    });

    try {
      final result = await _updateService.checkForUpdate(
        currentVersionOverride: _currentVersion,
      );

      if (!mounted) return;

      setState(() {
        _isChecking = false;
        _checkResult = result;
        _lastCheckedTime = DateTime.now();

        if (result.status == UpdateCheckStatus.upToDate) {
          _statusMessage = '✓ तुमचे अॅप अद्ययावत आहे.';
        } else if (result.status == UpdateCheckStatus.updateAvailable) {
          _statusMessage = 'नवीन अपडेट उपलब्ध आहे';
        } else if (result.status == UpdateCheckStatus.noApkAvailable) {
          _statusMessage = null;
          _errorMessage = result.errorMessage ?? 'या आवृत्तीसाठी APK उपलब्ध नाही.';
        } else if (result.status == UpdateCheckStatus.error) {
          _statusMessage = null;
          _errorMessage = result.errorMessage ??
              'अपडेट तपासताना त्रुटी आढळली. कृपया थोड्या वेळाने प्रयत्न करा.';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isChecking = false;
        _errorMessage = 'इंटरनेट कनेक्शन उपलब्ध नाही.';
        _statusMessage = null;
        _lastCheckedTime = DateTime.now();
      });
    }
  }

  /// Prompts the user and opens Android system settings for "Install unknown apps".
  /// Chrome or any browser is NEVER opened.
  Future<void> _openInstallPermissionDialog() async {
    if (!mounted) return;

    final shouldOpenSettings = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          icon: const Icon(
            Icons.security_update_good_rounded,
            color: _deepSaffron,
            size: 40,
          ),
          title: const Text(
            'अॅप इन्स्टॉल परवानगी आवश्यक',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            textAlign: TextAlign.center,
          ),
          content: const Text(
            'नवीन अपडेट थेट इन्स्टॉल करण्यासाठी Android ला '
            '\'अज्ञात अॅप्स इन्स्टॉल करा\' (Install unknown apps) ही परवानगी आवश्यक आहे.\n\n'
            'कृपया पुढील स्क्रीनवर या अॅपसाठी "Allow from this source" सुरू करा.',
            style: TextStyle(fontSize: 14, height: 1.4),
          ),
          actions: [
            if (!widget.isMandatory)
              TextButton(
                onPressed: () {
                  _pendingUpdateInfo = null;
                  Navigator.of(dialogContext).pop(false);
                },
                child:
                    const Text('रद्द करा', style: TextStyle(color: Colors.grey)),
              ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(backgroundColor: _saffron),
              child: const Text('सेटिंग्ज उघडा'),
            ),
          ],
        );
      },
    );

    if (shouldOpenSettings == true) {
      await _updateService.openInstallPermissionSettings();
    } else {
      _pendingUpdateInfo = null;
    }
  }

  /// Handles "Update Now" action:
  /// First-time: checks permission. If not granted, opens system settings.
  /// If already granted: directly downloads APK and opens installer.
  Future<void> _handleUpdateNowTapped(UpdateInfo info) async {
    if (_isDownloading) return;

    final apkUrl = info.apkDownloadUrl;
    if (apkUrl == null || apkUrl.isEmpty) {
      setState(() {
        _errorMessage = 'या आवृत्तीसाठी APK उपलब्ध नाही.';
      });
      return;
    }

    // 1. Check Android "Install unknown apps" permission first
    final canInstall = await _updateService.canInstallPackages();
    if (!canInstall) {
      // Permission not yet granted. Prompt user and open Android system settings
      _pendingUpdateInfo = info;
      await _openInstallPermissionDialog();
      return;
    }

    // 2. Permission already granted! Directly proceed to download & install
    await _startUpdateDownload(info);
  }

  Future<void> _startUpdateDownload(UpdateInfo info) async {
    if (_isDownloading) return;

    final apkUrl = info.apkDownloadUrl;
    if (apkUrl == null || apkUrl.isEmpty) {
      setState(() {
        _errorMessage = 'या आवृत्तीसाठी APK उपलब्ध नाही.';
      });
      return;
    }

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _downloadedBytes = 0;
      _totalBytes = info.apkSizeBytes;
      _errorMessage = null;
      _statusMessage = 'अपडेट डाउनलोड होत आहे...';
      _downloadedApkFile = null;
    });

    _cancelToken = UpdateCancelToken();

    try {
      final file = await _updateService.downloadApk(
        downloadUrl: apkUrl,
        onProgress: (progress, received, total) {
          if (mounted) {
            setState(() {
              _downloadProgress = progress;
              _downloadedBytes = received;
              if (total > 0) _totalBytes = total;
            });
          }
        },
        cancelToken: _cancelToken,
      );

      if (!mounted) return;

      setState(() {
        _isDownloading = false;
        _downloadProgress = 1.0;
        _downloadedApkFile = file;
        _statusMessage = 'Update download पूर्ण झाले.';
      });

      // Launch system installer directly
      await _launchInstaller(file.path);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _downloadProgress = 0.0;
        _errorMessage = 'Update download failed.\nकृपया पुन्हा प्रयत्न करा.';
      });
    }
  }

  Future<void> _launchInstaller(String filePath) async {
    try {
      final hasPermission = await _updateService.canInstallPackages();
      if (!hasPermission) {
        await _openInstallPermissionDialog();
        return;
      }

      await _updateService.installApk(filePath);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().replaceFirst('Exception: ', ''),
            style: const TextStyle(fontFamily: 'HindviDevanagari'),
          ),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 MB';
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.isMandatory,
      onPopInvokedWithResult: (didPop, result) {
        // If mandatory, user cannot bypass update by pressing Android back button
      },
      child: Scaffold(
        backgroundColor: _warmPaper,
        appBar: AppBar(
          title: Text(widget.isMandatory ? 'हिंदवी स्वराज्य' : 'App Update'),
          automaticallyImplyLeading: !widget.isMandatory,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Header Card (App identity, current version, last update version)
              _buildHeaderCard(),
              const SizedBox(height: 16),

              // 2. Status or Error messages
              if (_errorMessage != null) ...[
                _buildErrorCard(_errorMessage!),
                const SizedBox(height: 16),
              ],

              // 3. Content card based on update check state
              if (_checkResult != null) ...[
                if (_checkResult!.status == UpdateCheckStatus.upToDate)
                  _buildUpToDateCard()
                else if (_checkResult!.status ==
                    UpdateCheckStatus.updateAvailable)
                  _buildUpdateAvailableCard(_checkResult!.updateInfo!)
                else if (_checkResult!.status ==
                    UpdateCheckStatus.noApkAvailable)
                  _buildNoApkCard(_checkResult!.updateInfo!),
                const SizedBox(height: 16),
              ],

              // 4. Download Progress Card
              if (_isDownloading || _downloadedApkFile != null) ...[
                _buildDownloadProgressCard(),
                const SizedBox(height: 16),
              ],

              // 5. Action Button: Check for Updates (only in non-mandatory manual mode)
              if (!_isDownloading && !widget.isMandatory)
                _buildCheckForUpdateButton(),

              const SizedBox(height: 24),

              // 6. Information note about offline functionality & data safety
              _buildSafetyNoteCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard() {
    final latestVersionText = _checkResult?.latestVersion ?? _currentVersion;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFF0E6D9)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF0E1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.system_update_rounded,
                size: 34,
                color: _deepSaffron,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              widget.isMandatory ? 'हिंदवी स्वराज्य' : '📱 App Update',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: _ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              widget.isMandatory
                  ? 'नवीन अपडेट उपलब्ध आहे'
                  : 'हिंदवी स्वराज्य मंडळ व्यवस्थापन अॅपची नवीन आवृत्ती तपासा आणि थेट इन्स्टॉल करा.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF756A5D),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7EE),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFFE0BE)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Current Version (सध्याची आवृत्ती)',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF5A5248),
                        ),
                      ),
                      _isLoadingVersion
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: _saffron,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _currentVersion,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                    ],
                  ),
                  if (_checkResult != null) ...[
                    const Divider(height: 18, color: Color(0xFFFFE0BE)),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Latest Version (नवीनतम आवृत्ती)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF756A5D),
                          ),
                        ),
                        Text(
                          latestVersionText,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _deepSaffron,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (_lastCheckedTime != null) ...[
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'शेवटची तपासणी: ${_formatTime(_lastCheckedTime!)}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF9E8F7F),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (_isChecking) ...[
              const SizedBox(height: 16),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(_saffron),
                    ),
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Status: Checking... (तपासत आहे)',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _deepSaffron,
                    ),
                  ),
                ],
              ),
            ] else if (_statusMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                'Status: $_statusMessage',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _deepSaffron,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCheckForUpdateButton() {
    return ElevatedButton.icon(
      onPressed: _isChecking ? null : _checkForUpdate,
      icon: _isChecking
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.sync_rounded),
      label: Text(
        _isChecking ? 'Checking...' : 'Check for Updates',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: _saffron,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 2,
      ),
    );
  }

  Widget _buildUpToDateCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F8F1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFC3E6C3)),
      ),
      child: Column(
        children: [
          const Row(
            children: [
              Icon(Icons.check_circle_rounded,
                  color: Color(0xFF2E7D32), size: 24),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  '✓ तुमचे अॅप अद्ययावत आहे.',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2E7D32),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'तुमच्याकडे नवीन आवृत्ती ($_currentVersion) आधीपासून स्थापित आहे.',
              style: const TextStyle(fontSize: 13, color: Color(0xFF388E3C)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUpdateAvailableCard(UpdateInfo info) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFFCC99)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14FF7A00),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '🚀',
                style: TextStyle(fontSize: 22),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'नवीन अपडेट उपलब्ध आहे',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: _deepSaffron,
                  ),
                ),
              ),
              if (info.apkSizeBytes > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF0E1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _formatBytes(info.apkSizeBytes),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _deepSaffron,
                    ),
                  ),
                ),
            ],
          ),
          const Divider(height: 24, color: Color(0xFFF0E6D9)),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Current Version (सध्याची आवृत्ती)',
                      style: TextStyle(fontSize: 12, color: Color(0xFF756A5D)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _currentVersion,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _ink,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_rounded,
                color: _deepSaffron,
                size: 20,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'New Version (नवीन आवृत्ती)',
                      style: TextStyle(fontSize: 12, color: Color(0xFF756A5D)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      info.versionName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: _deepSaffron,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Release Notes Section
          if (info.body.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text(
              'या अपडेटमध्ये (Release Notes):',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _ink,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFAF7F2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFEDE3D5)),
              ),
              child: Text(
                info.body.trim(),
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF4A443C),
                  height: 1.4,
                ),
              ),
            ),
          ],

          const SizedBox(height: 18),

          // Update Now / Retry Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isDownloading
                  ? null
                  : () => _handleUpdateNowTapped(info),
              icon: Icon(_errorMessage != null && !_isDownloading
                  ? Icons.refresh_rounded
                  : Icons.download_rounded),
              label: Text(
                _errorMessage != null && !_isDownloading
                    ? 'Retry'
                    : 'Update Now',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _deepSaffron,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoApkCard(UpdateInfo info) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF9E6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFE082)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: Color(0xFFE65100), size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'नवीन आवृत्ती (${info.versionName}) आढळली',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFE65100),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'या आवृत्तीसाठी APK उपलब्ध नाही.',
            style: TextStyle(fontSize: 13, color: Color(0xFF756A5D)),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadProgressCard() {
    final percentInt = (_downloadProgress * 100).toInt();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF0E6D9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _downloadedApkFile != null
                    ? '✓ Update download पूर्ण झाले.'
                    : 'अपडेट डाउनलोड होत आहे...',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: _downloadedApkFile != null
                      ? const Color(0xFF2E7D32)
                      : _ink,
                ),
              ),
              Text(
                '$percentInt%',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: _deepSaffron,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: _isDownloading
                  ? (_downloadProgress > 0 ? _downloadProgress : null)
                  : 1.0,
              minHeight: 8,
              backgroundColor: const Color(0xFFF0EBE3),
              valueColor: AlwaysStoppedAnimation<Color>(
                _downloadedApkFile != null
                    ? const Color(0xFF2E7D32)
                    : _saffron,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _totalBytes > 0
                    ? '${_formatBytes(_downloadedBytes)} / ${_formatBytes(_totalBytes)}'
                    : _formatBytes(_downloadedBytes),
                style: const TextStyle(fontSize: 12, color: Color(0xFF756A5D)),
              ),
              if (_isDownloading && !widget.isMandatory)
                TextButton(
                  onPressed: () {
                    _cancelToken?.cancel();
                    setState(() {
                      _isDownloading = false;
                      _errorMessage = 'डाउनलोड वापरकर्त्याने रद्द केले.';
                    });
                  },
                  child: const Text(
                    'रद्द करा',
                    style: TextStyle(color: Colors.red, fontSize: 13),
                  ),
                ),
              if (_downloadedApkFile != null)
                TextButton.icon(
                  onPressed: () => _launchInstaller(_downloadedApkFile!.path),
                  icon: const Icon(Icons.install_mobile_rounded, size: 16),
                  label: const Text(
                    'इन्स्टॉल करा',
                    style: TextStyle(
                      color: _deepSaffron,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard(String error) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFCDD2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded,
              color: Colors.red, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              error,
              style: const TextStyle(
                color: Color(0xFFC62828),
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSafetyNoteCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7EE),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFE0BE)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield_outlined, color: _deepSaffron, size: 20),
              SizedBox(width: 8),
              Text(
                'डेटा सुरक्षिततेची हमी',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: _deepSaffron,
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            'अॅप अपडेट केल्यावर तुमचा पूर्वीचा सर्व डेटा (वर्गणी, खर्च, प्रसाद देणगी) पूर्णपणे सुरक्षित राहतो. कोणताही डेटा डिलीट होत नाही.',
            style:
                TextStyle(fontSize: 12, color: Color(0xFF555555), height: 1.4),
          ),
        ],
      ),
    );
  }
}
