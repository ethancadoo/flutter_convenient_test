import 'package:convenient_test_common_dart/convenient_test_common_dart.dart';
import 'package:convenient_test_manager_dart/misc/compile_time_config.dart';
import 'package:convenient_test_manager_dart/services/misc_dart_service.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:get_it/get_it.dart';
import 'package:mobx/mobx.dart';

part 'worker_super_run_store.freezed.dart';

part 'worker_super_run_store.g.dart';

/// A "worker run" is the code execution from worker hot-restart to the next hot-restart
/// A "worker super run" is one or multiple "worker run"s
class WorkerSuperRunStore = _WorkerSuperRunStore with _$WorkerSuperRunStore;

abstract class _WorkerSuperRunStore with Store {
  static const _kTag = 'WorkerSuperRunStore';

  @observable
  bool isolationMode = CompileTimeConfig.kDefaultEnableIsolationMode;

  @observable
  WorkerSuperRunController currSuperRunController =
      _WorkerSuperRunControllerIntegrationTestClassicalMode(filterNameRegex: kRegexMatchNothing);

  void setInteractiveApp() => currSuperRunController = _WorkerSuperRunControllerInteractiveApp();

  void setIntegrationTest({required String filterNameRegex}) => currSuperRunController = isolationMode
      ? _WorkerSuperRunControllerIntegrationTestIsolationMode(filterNameRegex: filterNameRegex)
      : _WorkerSuperRunControllerIntegrationTestClassicalMode(filterNameRegex: filterNameRegex);

  _WorkerSuperRunStore() {
    Log.d(_kTag, 'CompileTimeConfig.kDefaultEnableIsolationMode=${CompileTimeConfig.kDefaultEnableIsolationMode}');

    reaction<bool>(
      (_) => isolationMode,
      (isolationMode) async {
        Log.d(
            _kTag, 'see isolationMode($isolationMode) changed, thus reloadInfo to make currSuperRunController updated');
        await GetIt.I.get<MiscDartService>().reloadInfo();
        assert(isolationMode
            ? currSuperRunController is _WorkerSuperRunControllerIntegrationTestIsolationMode
            : currSuperRunController is _WorkerSuperRunControllerIntegrationTestClassicalMode);
      },
    );
  }
}

enum WorkerRunMode { interactiveApp, integrationTest }

abstract class WorkerSuperRunController {
  const WorkerSuperRunController._();

  WorkerCurrentRunConfig calcCurrentRunConfig();

  void handleTearDownAll(ResolvedExecutionFilterProto resolvedExecutionFilter);

  bool get isInteractiveApp => this is _WorkerSuperRunControllerInteractiveApp;

  bool? get isolationModeForIntegrationTest;
}

class _WorkerSuperRunControllerInteractiveApp extends WorkerSuperRunController {
  _WorkerSuperRunControllerInteractiveApp() : super._();

  @override
  WorkerCurrentRunConfig calcCurrentRunConfig() {
    return WorkerCurrentRunConfig(interactiveApp: WorkerCurrentRunConfig_InteractiveApp());
  }

  @override
  void handleTearDownAll(ResolvedExecutionFilterProto resolvedExecutionFilter) {}

  @override
  bool? get isolationModeForIntegrationTest => null;
}

/// "classical mode": no hot-restart between running two tests
class _WorkerSuperRunControllerIntegrationTestClassicalMode extends WorkerSuperRunController {
  final String filterNameRegex;

  _WorkerSuperRunControllerIntegrationTestClassicalMode({required this.filterNameRegex}) : super._();

  @override
  WorkerCurrentRunConfig calcCurrentRunConfig() {
    return WorkerCurrentRunConfig(
      integrationTest: WorkerCurrentRunConfig_IntegrationTest(
        reportSuiteInfo: true,
        executionFilter: ExecutionFilter(
          filterNameRegex: filterNameRegex,
          strategy: ExecutionFilter_Strategy(allMatch: ExecutionFilter_Strategy_AllMatch()),
        ),
      ),
    );
  }

  @override
  void handleTearDownAll(ResolvedExecutionFilterProto resolvedExecutionFilter) {}

  @override
  bool? get isolationModeForIntegrationTest => false;
}

/// "isolation mode": *has* hot-restart between running two tests
class _WorkerSuperRunControllerIntegrationTestIsolationMode extends WorkerSuperRunController {
  static const _kTag = 'WorkerSuperRunControllerIntegrationTestIsolationMode';

  final String filterNameRegex;

  var state = const _ITIMState.initial();

  _WorkerSuperRunControllerIntegrationTestIsolationMode({required this.filterNameRegex}) : super._();

  @override
  WorkerCurrentRunConfig calcCurrentRunConfig() {
    return WorkerCurrentRunConfig(
      integrationTest: WorkerCurrentRunConfig_IntegrationTest(
        reportSuiteInfo: state is _ITIMStateInitial,
        executionFilter: _calcExecutionFilter(),
      ),
    );
  }

  ExecutionFilter _calcExecutionFilter() => state.map(
        initial: (_) => ExecutionFilter(
          filterNameRegex: filterNameRegex,
          strategy: ExecutionFilter_Strategy(firstMatch: ExecutionFilter_Strategy_FirstMatch()),
        ),
        middle: (s) => ExecutionFilter(
          filterNameRegex: filterNameRegex,
          strategy: ExecutionFilter_Strategy(
            nextMatch: ExecutionFilter_Strategy_NextMatch(
              prevTestName: s.lastFinishedTestName,
            ),
          ),
        ),
        finished: (_) => ExecutionFilter(
          // NOTE use "regex match nothing"
          filterNameRegex: kRegexMatchNothing,
          strategy: ExecutionFilter_Strategy(allMatch: ExecutionFilter_Strategy_AllMatch()),
        ),
      );

  @override
  void handleTearDownAll(ResolvedExecutionFilterProto resolvedExecutionFilter) {
    final allowExecuteTestNames = resolvedExecutionFilter.allowExecuteTestNames;
    final oldState = state;

    if (allowExecuteTestNames.isEmpty) {
      state = const _ITIMState.finished();
    } else {
      state = _ITIMState.middle(lastFinishedTestName: allowExecuteTestNames.single);
    }
    Log.d(_kTag, 'handleTearDownAll oldState=$oldState newState=$state allowExecuteTestNames=$allowExecuteTestNames');
  }

  @override
  bool? get isolationModeForIntegrationTest => true;
}

// ITIM := IntegrationTestIsolationMode
@freezed
class _ITIMState with _$_ITIMState {
  /// Before first test finished
  const factory _ITIMState.initial() = _ITIMStateInitial;

  const factory _ITIMState.middle({
    required String lastFinishedTestName,
  }) = _ITIMStateMiddle;

  const factory _ITIMState.finished() = _ITIMStateFinished;
}
