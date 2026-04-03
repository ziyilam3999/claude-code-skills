---
name: flutter
description: >
  Flutter/Dart development patterns including Riverpod state management,
  go_router navigation, and mobile best practices. Use when working with
  *.dart files, pubspec.yaml, Flutter widgets, Riverpod providers, go_router
  routes, or any Flutter/Dart development task.
---

# Flutter Best Practices

## State Management (Riverpod)

### Controller Pattern
```dart
@riverpod
class ExampleController extends _$ExampleController {
  @override
  AsyncValue<Data> build() => const AsyncValue.loading();

  Future<void> fetchData() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _api.getData());
  }
}
```

### Provider Usage
```dart
// Good - Read in build
final data = ref.watch(exampleControllerProvider);

// Good - Call methods
ref.read(exampleControllerProvider.notifier).fetchData();

// Bad - Watch notifier
ref.watch(exampleControllerProvider.notifier); // Don't do this
```

## Navigation (go_router)

### Route Definition
```dart
final router = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const HomeScreen(),
      routes: [
        GoRoute(
          path: 'details/:id',
          builder: (context, state) => DetailsScreen(
            id: state.pathParameters['id']!,
          ),
        ),
      ],
    ),
  ],
);
```

## Widget Best Practices

### Const Constructors
```dart
// Good - enables widget reuse
const Text('Hello')
const MyWidget(key: Key('test'))

// Bad - rebuilds every time
Text('Hello')
```

### Build Method Size
- Keep `build()` methods < 50 lines
- Extract widgets to separate methods/classes
- Use composition over inheritance

## Naming Conventions

| Type | Convention | Example |
|------|------------|---------|
| Files | snake_case.dart | park_status_model.dart |
| Classes | PascalCase | ParkStatusModel |
| Variables | camelCase | parkStatusModel |
| Private | _camelCase | _currentPosition |
| Providers | camelCaseProvider | apiServiceProvider |

## Testing

### Widget Test Pattern
```dart
testWidgets('shows loading then data', (tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [dataProvider.overrideWith((_) => mockData)],
      child: const MaterialApp(home: MyScreen()),
    ),
  );

  expect(find.byType(CircularProgressIndicator), findsOneWidget);
  await tester.pumpAndSettle();
  expect(find.text('Data loaded'), findsOneWidget);
});
```

## API Service Pattern

```dart
Future<GSApiBaseResponseModel<UserModel>> getUser({
  required String userId,
}) async {
  final dynamic response = await getRequest(
    '${ApiEndpoints.user}/$userId',
  );

  return GSApiBaseResponseModel<UserModel>.fromJson(
    response,
    (json) => UserModel.fromJson(json as Map<String, dynamic>),
  );
}
```

## Polling Pattern

```dart
Timer? _timer;
static const _pollInterval = Duration(seconds: 3);

void _startPolling() {
  _timer?.cancel();
  _timer = Timer.periodic(_pollInterval, (_) => _fetchStatus());
}

void _stopPolling() {
  _timer?.cancel();
  _timer = null;
}

// In build():
ref.onDispose(_stopPolling);
```

## Error Handling

```dart
// Use AsyncValue for loading/error states
ref.watch(dataProvider).when(
  data: (data) => DataWidget(data),
  loading: () => const CircularProgressIndicator(),
  error: (error, stack) => ErrorWidget(error.toString()),
);
```

## Run Data Recording

After the skill is applied (or referenced/errors), persist run data. This section always runs regardless of outcome.

**Resolve the skill base directory** from the symlink target (the skill's source directory), not the current working directory.

### What to record

Append to `runs/data.json` (create with `{"skill":"flutter","lastRun":null,"totalRuns":0,"runs":[]}` if missing):

```json
{
  "timestamp": "{ISO-8601}",
  "outcome": "applied|referenced|error",
  "project": "{current project directory name}",
  "patternsApplied": "{number of patterns applied or referenced}",
  "filesModified": "{number of files modified}",
  "summary": "{one-line: e.g., '3 patterns applied across 2 files'}"
}
```

Keep last 20 runs. Set `lastRun` and increment `totalRuns`.

Append one line to `runs/run.log` (keep last 100 lines):
```
{timestamp} | {outcome} | {patternsApplied} patterns | {summary}
```

Do not fail the skill if recording fails -- log a warning and continue.
