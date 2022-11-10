import 'dart:io';
import 'dart:typed_data';

import 'package:convenient_test_common_dart/convenient_test_common_dart.dart';
import 'package:convenient_test_manager_dart/services/fs_service.dart';
import 'package:convenient_test_manager_dart/stores/global_config_store.dart';
import 'package:get_it/get_it.dart';
import 'package:mobx/mobx.dart';

part 'report_saver_service.g.dart';

class ReportSaverService = _ReportSaverService with _$ReportSaverService;

abstract class _ReportSaverService with Store {
  static const _kTag = 'ReportSaverService';

  bool get enable => GlobalConfigStore.config.enableReportSaver;
  set enable(bool val) => GlobalConfigStore.config.enableReportSaver = val;

  Future<void> save(ReportCollection request) async {
    if (!enable) return;

    // need to be sync, otherwise when two reports come together they may conflict

    final String folderPath = await _getReportDirectory();
    final String reportPath = '${folderPath}Report.$kReportFileExtension';

    File(reportPath)
        .writeAsBytesSync(request.writeToBuffer(), mode: FileMode.append);

    if (GlobalConfigStore.config.exportScreenshots) {
      final dir = Directory('${folderPath}screenshots/');
      dir.createSync();

      for (final item in request.items) {
        if (item.whichSubType() == ReportItem_SubType.snapshot) {
          File('${dir.path}${item.snapshot.logEntryId}.png')
              .writeAsBytesSync(item.snapshot.image as Uint8List);
        }
      }
    }
  }

  Future<void> clear() async {
    Log.d(_kTag, 'clear');
    final folder = Directory(await _getReportDirectory());
    if (folder.existsSync()) folder.deleteSync(recursive: true);
  }

  static Future<String> _getReportDirectory() async {
    return await GetIt.I
        .get<FsService>()
        .getActiveSuperRunDataSubDirectory(category: 'Report');
  }
}
