import 'workspace_storage.dart';

KeyValueBlobStorage createPlatformBlobStorage() => InMemoryBlobStorage();
