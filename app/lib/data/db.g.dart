// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'db.dart';

// ignore_for_file: type=lint
class $SettingsTable extends Settings with TableInfo<$SettingsTable, Setting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _deviceGuidMeta = const VerificationMeta(
    'deviceGuid',
  );
  @override
  late final GeneratedColumn<String> deviceGuid = GeneratedColumn<String>(
    'device_guid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _identityKeyMeta = const VerificationMeta(
    'identityKey',
  );
  @override
  late final GeneratedColumn<String> identityKey = GeneratedColumn<String>(
    'identity_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _nicknameMeta = const VerificationMeta(
    'nickname',
  );
  @override
  late final GeneratedColumn<String> nickname = GeneratedColumn<String>(
    'nickname',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _welcomeMessageMeta = const VerificationMeta(
    'welcomeMessage',
  );
  @override
  late final GeneratedColumn<String> welcomeMessage = GeneratedColumn<String>(
    'welcome_message',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  @override
  late final GeneratedColumnWithTypeConverter<AppTheme, int> theme =
      GeneratedColumn<int>(
        'theme',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
        defaultValue: Constant(AppTheme.system.index),
      ).withConverter<AppTheme>($SettingsTable.$convertertheme);
  @override
  late final GeneratedColumnWithTypeConverter<AppLanguage, int> language =
      GeneratedColumn<int>(
        'language',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
        defaultValue: Constant(AppLanguage.english.index),
      ).withConverter<AppLanguage>($SettingsTable.$converterlanguage);
  static const VerificationMeta _tcpPortMeta = const VerificationMeta(
    'tcpPort',
  );
  @override
  late final GeneratedColumn<int> tcpPort = GeneratedColumn<int>(
    'tcp_port',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(defaultTcpPort),
  );
  static const VerificationMeta _backgroundMeta = const VerificationMeta(
    'background',
  );
  @override
  late final GeneratedColumn<int> background = GeneratedColumn<int>(
    'background',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _retentionDaysMeta = const VerificationMeta(
    'retentionDays',
  );
  @override
  late final GeneratedColumn<int> retentionDays = GeneratedColumn<int>(
    'retention_days',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _updateChecksMeta = const VerificationMeta(
    'updateChecks',
  );
  @override
  late final GeneratedColumn<bool> updateChecks = GeneratedColumn<bool>(
    'update_checks',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("update_checks" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _lastUpdateCheckMeta = const VerificationMeta(
    'lastUpdateCheck',
  );
  @override
  late final GeneratedColumn<DateTime> lastUpdateCheck =
      GeneratedColumn<DateTime>(
        'last_update_check',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    deviceGuid,
    identityKey,
    nickname,
    welcomeMessage,
    theme,
    language,
    tcpPort,
    background,
    retentionDays,
    updateChecks,
    lastUpdateCheck,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<Setting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('device_guid')) {
      context.handle(
        _deviceGuidMeta,
        deviceGuid.isAcceptableOrUnknown(data['device_guid']!, _deviceGuidMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceGuidMeta);
    }
    if (data.containsKey('identity_key')) {
      context.handle(
        _identityKeyMeta,
        identityKey.isAcceptableOrUnknown(
          data['identity_key']!,
          _identityKeyMeta,
        ),
      );
    }
    if (data.containsKey('nickname')) {
      context.handle(
        _nicknameMeta,
        nickname.isAcceptableOrUnknown(data['nickname']!, _nicknameMeta),
      );
    } else if (isInserting) {
      context.missing(_nicknameMeta);
    }
    if (data.containsKey('welcome_message')) {
      context.handle(
        _welcomeMessageMeta,
        welcomeMessage.isAcceptableOrUnknown(
          data['welcome_message']!,
          _welcomeMessageMeta,
        ),
      );
    }
    if (data.containsKey('tcp_port')) {
      context.handle(
        _tcpPortMeta,
        tcpPort.isAcceptableOrUnknown(data['tcp_port']!, _tcpPortMeta),
      );
    }
    if (data.containsKey('background')) {
      context.handle(
        _backgroundMeta,
        background.isAcceptableOrUnknown(data['background']!, _backgroundMeta),
      );
    }
    if (data.containsKey('retention_days')) {
      context.handle(
        _retentionDaysMeta,
        retentionDays.isAcceptableOrUnknown(
          data['retention_days']!,
          _retentionDaysMeta,
        ),
      );
    }
    if (data.containsKey('update_checks')) {
      context.handle(
        _updateChecksMeta,
        updateChecks.isAcceptableOrUnknown(
          data['update_checks']!,
          _updateChecksMeta,
        ),
      );
    }
    if (data.containsKey('last_update_check')) {
      context.handle(
        _lastUpdateCheckMeta,
        lastUpdateCheck.isAcceptableOrUnknown(
          data['last_update_check']!,
          _lastUpdateCheckMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Setting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Setting(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      deviceGuid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_guid'],
      )!,
      identityKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}identity_key'],
      )!,
      nickname: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}nickname'],
      )!,
      welcomeMessage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}welcome_message'],
      )!,
      theme: $SettingsTable.$convertertheme.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}theme'],
        )!,
      ),
      language: $SettingsTable.$converterlanguage.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}language'],
        )!,
      ),
      tcpPort: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}tcp_port'],
      )!,
      background: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}background'],
      )!,
      retentionDays: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}retention_days'],
      )!,
      updateChecks: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}update_checks'],
      )!,
      lastUpdateCheck: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_update_check'],
      ),
    );
  }

  @override
  $SettingsTable createAlias(String alias) {
    return $SettingsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<AppTheme, int, int> $convertertheme =
      const EnumIndexConverter<AppTheme>(AppTheme.values);
  static JsonTypeConverter2<AppLanguage, int, int> $converterlanguage =
      const EnumIndexConverter<AppLanguage>(AppLanguage.values);
}

class Setting extends DataClass implements Insertable<Setting> {
  final int id;

  /// Identyfikator urządzenia. Od schematu v6 nie jest losowany, tylko liczony
  /// z klucza publicznego (patrz `ChattCrypto.guidFromPublicKey`).
  final String deviceGuid;

  /// Klucz prywatny tożsamości (base64, X25519). To on jest urządzeniem:
  /// z niego wychodzi klucz publiczny, a z niego identyfikator.
  final String identityKey;
  final String nickname;
  final String welcomeMessage;
  final AppTheme theme;

  /// Domyślnie angielski, a nie język systemu: aplikacja jest wydawana
  /// międzynarodowo, więc pierwsze uruchomienie ma być zrozumiałe wszędzie.
  /// Polski i „za systemem" są o jedno dotknięcie w Ustawieniach.
  final AppLanguage language;

  /// Preferowany port serwera. Faktyczny port może być inny, gdy ten jest
  /// zajęty (patrz DeviceIdentity.tcpPort).
  final int tcpPort;

  /// Numer wybranego tła (patrz `ui/backgrounds.dart`). 0 znaczy „bez tła".
  final int background;

  /// Po ilu dniach kasować wiadomości. 0 znaczy „trzymaj bez końca".
  /// Kasowanie dotyczy wpisów w bazie; odebrane pliki zostają na dysku.
  final int retentionDays;

  /// Czy aplikacja sama pyta GitHuba o nowsze wydanie. Domyślnie nie:
  /// to jedyny ruch poza sieć lokalną, więc włącza go użytkownik świadomie.
  final bool updateChecks;

  /// Kiedy ostatnio padło pytanie o wydanie. Po tym poznajemy, że minęła doba
  /// i wypada zapytać znowu.
  final DateTime? lastUpdateCheck;
  const Setting({
    required this.id,
    required this.deviceGuid,
    required this.identityKey,
    required this.nickname,
    required this.welcomeMessage,
    required this.theme,
    required this.language,
    required this.tcpPort,
    required this.background,
    required this.retentionDays,
    required this.updateChecks,
    this.lastUpdateCheck,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['device_guid'] = Variable<String>(deviceGuid);
    map['identity_key'] = Variable<String>(identityKey);
    map['nickname'] = Variable<String>(nickname);
    map['welcome_message'] = Variable<String>(welcomeMessage);
    {
      map['theme'] = Variable<int>($SettingsTable.$convertertheme.toSql(theme));
    }
    {
      map['language'] = Variable<int>(
        $SettingsTable.$converterlanguage.toSql(language),
      );
    }
    map['tcp_port'] = Variable<int>(tcpPort);
    map['background'] = Variable<int>(background);
    map['retention_days'] = Variable<int>(retentionDays);
    map['update_checks'] = Variable<bool>(updateChecks);
    if (!nullToAbsent || lastUpdateCheck != null) {
      map['last_update_check'] = Variable<DateTime>(lastUpdateCheck);
    }
    return map;
  }

  SettingsCompanion toCompanion(bool nullToAbsent) {
    return SettingsCompanion(
      id: Value(id),
      deviceGuid: Value(deviceGuid),
      identityKey: Value(identityKey),
      nickname: Value(nickname),
      welcomeMessage: Value(welcomeMessage),
      theme: Value(theme),
      language: Value(language),
      tcpPort: Value(tcpPort),
      background: Value(background),
      retentionDays: Value(retentionDays),
      updateChecks: Value(updateChecks),
      lastUpdateCheck: lastUpdateCheck == null && nullToAbsent
          ? const Value.absent()
          : Value(lastUpdateCheck),
    );
  }

  factory Setting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Setting(
      id: serializer.fromJson<int>(json['id']),
      deviceGuid: serializer.fromJson<String>(json['deviceGuid']),
      identityKey: serializer.fromJson<String>(json['identityKey']),
      nickname: serializer.fromJson<String>(json['nickname']),
      welcomeMessage: serializer.fromJson<String>(json['welcomeMessage']),
      theme: $SettingsTable.$convertertheme.fromJson(
        serializer.fromJson<int>(json['theme']),
      ),
      language: $SettingsTable.$converterlanguage.fromJson(
        serializer.fromJson<int>(json['language']),
      ),
      tcpPort: serializer.fromJson<int>(json['tcpPort']),
      background: serializer.fromJson<int>(json['background']),
      retentionDays: serializer.fromJson<int>(json['retentionDays']),
      updateChecks: serializer.fromJson<bool>(json['updateChecks']),
      lastUpdateCheck: serializer.fromJson<DateTime?>(json['lastUpdateCheck']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'deviceGuid': serializer.toJson<String>(deviceGuid),
      'identityKey': serializer.toJson<String>(identityKey),
      'nickname': serializer.toJson<String>(nickname),
      'welcomeMessage': serializer.toJson<String>(welcomeMessage),
      'theme': serializer.toJson<int>(
        $SettingsTable.$convertertheme.toJson(theme),
      ),
      'language': serializer.toJson<int>(
        $SettingsTable.$converterlanguage.toJson(language),
      ),
      'tcpPort': serializer.toJson<int>(tcpPort),
      'background': serializer.toJson<int>(background),
      'retentionDays': serializer.toJson<int>(retentionDays),
      'updateChecks': serializer.toJson<bool>(updateChecks),
      'lastUpdateCheck': serializer.toJson<DateTime?>(lastUpdateCheck),
    };
  }

  Setting copyWith({
    int? id,
    String? deviceGuid,
    String? identityKey,
    String? nickname,
    String? welcomeMessage,
    AppTheme? theme,
    AppLanguage? language,
    int? tcpPort,
    int? background,
    int? retentionDays,
    bool? updateChecks,
    Value<DateTime?> lastUpdateCheck = const Value.absent(),
  }) => Setting(
    id: id ?? this.id,
    deviceGuid: deviceGuid ?? this.deviceGuid,
    identityKey: identityKey ?? this.identityKey,
    nickname: nickname ?? this.nickname,
    welcomeMessage: welcomeMessage ?? this.welcomeMessage,
    theme: theme ?? this.theme,
    language: language ?? this.language,
    tcpPort: tcpPort ?? this.tcpPort,
    background: background ?? this.background,
    retentionDays: retentionDays ?? this.retentionDays,
    updateChecks: updateChecks ?? this.updateChecks,
    lastUpdateCheck: lastUpdateCheck.present
        ? lastUpdateCheck.value
        : this.lastUpdateCheck,
  );
  Setting copyWithCompanion(SettingsCompanion data) {
    return Setting(
      id: data.id.present ? data.id.value : this.id,
      deviceGuid: data.deviceGuid.present
          ? data.deviceGuid.value
          : this.deviceGuid,
      identityKey: data.identityKey.present
          ? data.identityKey.value
          : this.identityKey,
      nickname: data.nickname.present ? data.nickname.value : this.nickname,
      welcomeMessage: data.welcomeMessage.present
          ? data.welcomeMessage.value
          : this.welcomeMessage,
      theme: data.theme.present ? data.theme.value : this.theme,
      language: data.language.present ? data.language.value : this.language,
      tcpPort: data.tcpPort.present ? data.tcpPort.value : this.tcpPort,
      background: data.background.present
          ? data.background.value
          : this.background,
      retentionDays: data.retentionDays.present
          ? data.retentionDays.value
          : this.retentionDays,
      updateChecks: data.updateChecks.present
          ? data.updateChecks.value
          : this.updateChecks,
      lastUpdateCheck: data.lastUpdateCheck.present
          ? data.lastUpdateCheck.value
          : this.lastUpdateCheck,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Setting(')
          ..write('id: $id, ')
          ..write('deviceGuid: $deviceGuid, ')
          ..write('identityKey: $identityKey, ')
          ..write('nickname: $nickname, ')
          ..write('welcomeMessage: $welcomeMessage, ')
          ..write('theme: $theme, ')
          ..write('language: $language, ')
          ..write('tcpPort: $tcpPort, ')
          ..write('background: $background, ')
          ..write('retentionDays: $retentionDays, ')
          ..write('updateChecks: $updateChecks, ')
          ..write('lastUpdateCheck: $lastUpdateCheck')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    deviceGuid,
    identityKey,
    nickname,
    welcomeMessage,
    theme,
    language,
    tcpPort,
    background,
    retentionDays,
    updateChecks,
    lastUpdateCheck,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Setting &&
          other.id == this.id &&
          other.deviceGuid == this.deviceGuid &&
          other.identityKey == this.identityKey &&
          other.nickname == this.nickname &&
          other.welcomeMessage == this.welcomeMessage &&
          other.theme == this.theme &&
          other.language == this.language &&
          other.tcpPort == this.tcpPort &&
          other.background == this.background &&
          other.retentionDays == this.retentionDays &&
          other.updateChecks == this.updateChecks &&
          other.lastUpdateCheck == this.lastUpdateCheck);
}

class SettingsCompanion extends UpdateCompanion<Setting> {
  final Value<int> id;
  final Value<String> deviceGuid;
  final Value<String> identityKey;
  final Value<String> nickname;
  final Value<String> welcomeMessage;
  final Value<AppTheme> theme;
  final Value<AppLanguage> language;
  final Value<int> tcpPort;
  final Value<int> background;
  final Value<int> retentionDays;
  final Value<bool> updateChecks;
  final Value<DateTime?> lastUpdateCheck;
  const SettingsCompanion({
    this.id = const Value.absent(),
    this.deviceGuid = const Value.absent(),
    this.identityKey = const Value.absent(),
    this.nickname = const Value.absent(),
    this.welcomeMessage = const Value.absent(),
    this.theme = const Value.absent(),
    this.language = const Value.absent(),
    this.tcpPort = const Value.absent(),
    this.background = const Value.absent(),
    this.retentionDays = const Value.absent(),
    this.updateChecks = const Value.absent(),
    this.lastUpdateCheck = const Value.absent(),
  });
  SettingsCompanion.insert({
    this.id = const Value.absent(),
    required String deviceGuid,
    this.identityKey = const Value.absent(),
    required String nickname,
    this.welcomeMessage = const Value.absent(),
    this.theme = const Value.absent(),
    this.language = const Value.absent(),
    this.tcpPort = const Value.absent(),
    this.background = const Value.absent(),
    this.retentionDays = const Value.absent(),
    this.updateChecks = const Value.absent(),
    this.lastUpdateCheck = const Value.absent(),
  }) : deviceGuid = Value(deviceGuid),
       nickname = Value(nickname);
  static Insertable<Setting> custom({
    Expression<int>? id,
    Expression<String>? deviceGuid,
    Expression<String>? identityKey,
    Expression<String>? nickname,
    Expression<String>? welcomeMessage,
    Expression<int>? theme,
    Expression<int>? language,
    Expression<int>? tcpPort,
    Expression<int>? background,
    Expression<int>? retentionDays,
    Expression<bool>? updateChecks,
    Expression<DateTime>? lastUpdateCheck,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (deviceGuid != null) 'device_guid': deviceGuid,
      if (identityKey != null) 'identity_key': identityKey,
      if (nickname != null) 'nickname': nickname,
      if (welcomeMessage != null) 'welcome_message': welcomeMessage,
      if (theme != null) 'theme': theme,
      if (language != null) 'language': language,
      if (tcpPort != null) 'tcp_port': tcpPort,
      if (background != null) 'background': background,
      if (retentionDays != null) 'retention_days': retentionDays,
      if (updateChecks != null) 'update_checks': updateChecks,
      if (lastUpdateCheck != null) 'last_update_check': lastUpdateCheck,
    });
  }

  SettingsCompanion copyWith({
    Value<int>? id,
    Value<String>? deviceGuid,
    Value<String>? identityKey,
    Value<String>? nickname,
    Value<String>? welcomeMessage,
    Value<AppTheme>? theme,
    Value<AppLanguage>? language,
    Value<int>? tcpPort,
    Value<int>? background,
    Value<int>? retentionDays,
    Value<bool>? updateChecks,
    Value<DateTime?>? lastUpdateCheck,
  }) {
    return SettingsCompanion(
      id: id ?? this.id,
      deviceGuid: deviceGuid ?? this.deviceGuid,
      identityKey: identityKey ?? this.identityKey,
      nickname: nickname ?? this.nickname,
      welcomeMessage: welcomeMessage ?? this.welcomeMessage,
      theme: theme ?? this.theme,
      language: language ?? this.language,
      tcpPort: tcpPort ?? this.tcpPort,
      background: background ?? this.background,
      retentionDays: retentionDays ?? this.retentionDays,
      updateChecks: updateChecks ?? this.updateChecks,
      lastUpdateCheck: lastUpdateCheck ?? this.lastUpdateCheck,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (deviceGuid.present) {
      map['device_guid'] = Variable<String>(deviceGuid.value);
    }
    if (identityKey.present) {
      map['identity_key'] = Variable<String>(identityKey.value);
    }
    if (nickname.present) {
      map['nickname'] = Variable<String>(nickname.value);
    }
    if (welcomeMessage.present) {
      map['welcome_message'] = Variable<String>(welcomeMessage.value);
    }
    if (theme.present) {
      map['theme'] = Variable<int>(
        $SettingsTable.$convertertheme.toSql(theme.value),
      );
    }
    if (language.present) {
      map['language'] = Variable<int>(
        $SettingsTable.$converterlanguage.toSql(language.value),
      );
    }
    if (tcpPort.present) {
      map['tcp_port'] = Variable<int>(tcpPort.value);
    }
    if (background.present) {
      map['background'] = Variable<int>(background.value);
    }
    if (retentionDays.present) {
      map['retention_days'] = Variable<int>(retentionDays.value);
    }
    if (updateChecks.present) {
      map['update_checks'] = Variable<bool>(updateChecks.value);
    }
    if (lastUpdateCheck.present) {
      map['last_update_check'] = Variable<DateTime>(lastUpdateCheck.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingsCompanion(')
          ..write('id: $id, ')
          ..write('deviceGuid: $deviceGuid, ')
          ..write('identityKey: $identityKey, ')
          ..write('nickname: $nickname, ')
          ..write('welcomeMessage: $welcomeMessage, ')
          ..write('theme: $theme, ')
          ..write('language: $language, ')
          ..write('tcpPort: $tcpPort, ')
          ..write('background: $background, ')
          ..write('retentionDays: $retentionDays, ')
          ..write('updateChecks: $updateChecks, ')
          ..write('lastUpdateCheck: $lastUpdateCheck')
          ..write(')'))
        .toString();
  }
}

class $PeersTable extends Peers with TableInfo<$PeersTable, Peer> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PeersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _guidMeta = const VerificationMeta('guid');
  @override
  late final GeneratedColumn<String> guid = GeneratedColumn<String>(
    'guid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _welcomeMessageMeta = const VerificationMeta(
    'welcomeMessage',
  );
  @override
  late final GeneratedColumn<String> welcomeMessage = GeneratedColumn<String>(
    'welcome_message',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _hostMeta = const VerificationMeta('host');
  @override
  late final GeneratedColumn<String> host = GeneratedColumn<String>(
    'host',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _portMeta = const VerificationMeta('port');
  @override
  late final GeneratedColumn<int> port = GeneratedColumn<int>(
    'port',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _verifiedMeta = const VerificationMeta(
    'verified',
  );
  @override
  late final GeneratedColumn<bool> verified = GeneratedColumn<bool>(
    'verified',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("verified" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _publicKeyMeta = const VerificationMeta(
    'publicKey',
  );
  @override
  late final GeneratedColumn<String> publicKey = GeneratedColumn<String>(
    'public_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sessionKeyMeta = const VerificationMeta(
    'sessionKey',
  );
  @override
  late final GeneratedColumn<String> sessionKey = GeneratedColumn<String>(
    'session_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _aliasMeta = const VerificationMeta('alias');
  @override
  late final GeneratedColumn<String> alias = GeneratedColumn<String>(
    'alias',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _autoAcceptMeta = const VerificationMeta(
    'autoAccept',
  );
  @override
  late final GeneratedColumn<bool> autoAccept = GeneratedColumn<bool>(
    'auto_accept',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("auto_accept" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _firstSeenMeta = const VerificationMeta(
    'firstSeen',
  );
  @override
  late final GeneratedColumn<DateTime> firstSeen = GeneratedColumn<DateTime>(
    'first_seen',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastSeenMeta = const VerificationMeta(
    'lastSeen',
  );
  @override
  late final GeneratedColumn<DateTime> lastSeen = GeneratedColumn<DateTime>(
    'last_seen',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    guid,
    name,
    welcomeMessage,
    host,
    port,
    verified,
    publicKey,
    sessionKey,
    alias,
    autoAccept,
    firstSeen,
    lastSeen,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'peers';
  @override
  VerificationContext validateIntegrity(
    Insertable<Peer> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('guid')) {
      context.handle(
        _guidMeta,
        guid.isAcceptableOrUnknown(data['guid']!, _guidMeta),
      );
    } else if (isInserting) {
      context.missing(_guidMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('welcome_message')) {
      context.handle(
        _welcomeMessageMeta,
        welcomeMessage.isAcceptableOrUnknown(
          data['welcome_message']!,
          _welcomeMessageMeta,
        ),
      );
    }
    if (data.containsKey('host')) {
      context.handle(
        _hostMeta,
        host.isAcceptableOrUnknown(data['host']!, _hostMeta),
      );
    } else if (isInserting) {
      context.missing(_hostMeta);
    }
    if (data.containsKey('port')) {
      context.handle(
        _portMeta,
        port.isAcceptableOrUnknown(data['port']!, _portMeta),
      );
    } else if (isInserting) {
      context.missing(_portMeta);
    }
    if (data.containsKey('verified')) {
      context.handle(
        _verifiedMeta,
        verified.isAcceptableOrUnknown(data['verified']!, _verifiedMeta),
      );
    }
    if (data.containsKey('public_key')) {
      context.handle(
        _publicKeyMeta,
        publicKey.isAcceptableOrUnknown(data['public_key']!, _publicKeyMeta),
      );
    }
    if (data.containsKey('session_key')) {
      context.handle(
        _sessionKeyMeta,
        sessionKey.isAcceptableOrUnknown(data['session_key']!, _sessionKeyMeta),
      );
    }
    if (data.containsKey('alias')) {
      context.handle(
        _aliasMeta,
        alias.isAcceptableOrUnknown(data['alias']!, _aliasMeta),
      );
    }
    if (data.containsKey('auto_accept')) {
      context.handle(
        _autoAcceptMeta,
        autoAccept.isAcceptableOrUnknown(data['auto_accept']!, _autoAcceptMeta),
      );
    }
    if (data.containsKey('first_seen')) {
      context.handle(
        _firstSeenMeta,
        firstSeen.isAcceptableOrUnknown(data['first_seen']!, _firstSeenMeta),
      );
    } else if (isInserting) {
      context.missing(_firstSeenMeta);
    }
    if (data.containsKey('last_seen')) {
      context.handle(
        _lastSeenMeta,
        lastSeen.isAcceptableOrUnknown(data['last_seen']!, _lastSeenMeta),
      );
    } else if (isInserting) {
      context.missing(_lastSeenMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Peer map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Peer(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      guid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}guid'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      welcomeMessage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}welcome_message'],
      )!,
      host: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}host'],
      )!,
      port: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}port'],
      )!,
      verified: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}verified'],
      )!,
      publicKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}public_key'],
      ),
      sessionKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_key'],
      ),
      alias: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}alias'],
      ),
      autoAccept: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}auto_accept'],
      )!,
      firstSeen: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}first_seen'],
      )!,
      lastSeen: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_seen'],
      )!,
    );
  }

  @override
  $PeersTable createAlias(String alias) {
    return $PeersTable(attachedDatabase, alias);
  }
}

class Peer extends DataClass implements Insertable<Peer> {
  final int id;
  final String guid;
  final String name;
  final String welcomeMessage;
  final String host;
  final int port;
  final bool verified;

  /// Klucz publiczny rozmówcy (base64), przypięty przy pierwszym kontakcie.
  /// Jego zmiana znaczy albo reinstalację po drugiej stronie, albo próbę
  /// podszycia się, w obu przypadkach użytkownik ma to zobaczyć.
  final String? publicKey;

  /// Ślad po parowaniu z protokołu 4 (klucz sesji na zawsze). Od protokołu 5
  /// klucz sesji jest efemeryczny i nie trafia do bazy; kolumna zostaje na
  /// czas migracji i zniknie w kolejnym schemacie.
  final String? sessionKey;

  /// Własna nazwa rozmówcy, nadana lokalnie. [name] jest tym, co urządzenie
  /// samo o sobie rozgłasza, więc zmienia się bez pytania i każdy może wpisać
  /// tam cokolwiek. Alias zostaje po naszej stronie i nigdzie nie jedzie.
  /// Pusty i null znaczą to samo: idziemy za nazwą rozgłaszaną.
  final String? alias;

  /// Przyjmuj pliki od tego rozmówcy bez pytania. Ma sens wyłącznie przy
  /// potwierdzonej tożsamości, więc [setPeerVerified] gasi tę flagę razem
  /// z tarczą: inaczej przetrwałaby unieważnienie potwierdzenia.
  final bool autoAccept;
  final DateTime firstSeen;
  final DateTime lastSeen;
  const Peer({
    required this.id,
    required this.guid,
    required this.name,
    required this.welcomeMessage,
    required this.host,
    required this.port,
    required this.verified,
    this.publicKey,
    this.sessionKey,
    this.alias,
    required this.autoAccept,
    required this.firstSeen,
    required this.lastSeen,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['guid'] = Variable<String>(guid);
    map['name'] = Variable<String>(name);
    map['welcome_message'] = Variable<String>(welcomeMessage);
    map['host'] = Variable<String>(host);
    map['port'] = Variable<int>(port);
    map['verified'] = Variable<bool>(verified);
    if (!nullToAbsent || publicKey != null) {
      map['public_key'] = Variable<String>(publicKey);
    }
    if (!nullToAbsent || sessionKey != null) {
      map['session_key'] = Variable<String>(sessionKey);
    }
    if (!nullToAbsent || alias != null) {
      map['alias'] = Variable<String>(alias);
    }
    map['auto_accept'] = Variable<bool>(autoAccept);
    map['first_seen'] = Variable<DateTime>(firstSeen);
    map['last_seen'] = Variable<DateTime>(lastSeen);
    return map;
  }

  PeersCompanion toCompanion(bool nullToAbsent) {
    return PeersCompanion(
      id: Value(id),
      guid: Value(guid),
      name: Value(name),
      welcomeMessage: Value(welcomeMessage),
      host: Value(host),
      port: Value(port),
      verified: Value(verified),
      publicKey: publicKey == null && nullToAbsent
          ? const Value.absent()
          : Value(publicKey),
      sessionKey: sessionKey == null && nullToAbsent
          ? const Value.absent()
          : Value(sessionKey),
      alias: alias == null && nullToAbsent
          ? const Value.absent()
          : Value(alias),
      autoAccept: Value(autoAccept),
      firstSeen: Value(firstSeen),
      lastSeen: Value(lastSeen),
    );
  }

  factory Peer.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Peer(
      id: serializer.fromJson<int>(json['id']),
      guid: serializer.fromJson<String>(json['guid']),
      name: serializer.fromJson<String>(json['name']),
      welcomeMessage: serializer.fromJson<String>(json['welcomeMessage']),
      host: serializer.fromJson<String>(json['host']),
      port: serializer.fromJson<int>(json['port']),
      verified: serializer.fromJson<bool>(json['verified']),
      publicKey: serializer.fromJson<String?>(json['publicKey']),
      sessionKey: serializer.fromJson<String?>(json['sessionKey']),
      alias: serializer.fromJson<String?>(json['alias']),
      autoAccept: serializer.fromJson<bool>(json['autoAccept']),
      firstSeen: serializer.fromJson<DateTime>(json['firstSeen']),
      lastSeen: serializer.fromJson<DateTime>(json['lastSeen']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'guid': serializer.toJson<String>(guid),
      'name': serializer.toJson<String>(name),
      'welcomeMessage': serializer.toJson<String>(welcomeMessage),
      'host': serializer.toJson<String>(host),
      'port': serializer.toJson<int>(port),
      'verified': serializer.toJson<bool>(verified),
      'publicKey': serializer.toJson<String?>(publicKey),
      'sessionKey': serializer.toJson<String?>(sessionKey),
      'alias': serializer.toJson<String?>(alias),
      'autoAccept': serializer.toJson<bool>(autoAccept),
      'firstSeen': serializer.toJson<DateTime>(firstSeen),
      'lastSeen': serializer.toJson<DateTime>(lastSeen),
    };
  }

  Peer copyWith({
    int? id,
    String? guid,
    String? name,
    String? welcomeMessage,
    String? host,
    int? port,
    bool? verified,
    Value<String?> publicKey = const Value.absent(),
    Value<String?> sessionKey = const Value.absent(),
    Value<String?> alias = const Value.absent(),
    bool? autoAccept,
    DateTime? firstSeen,
    DateTime? lastSeen,
  }) => Peer(
    id: id ?? this.id,
    guid: guid ?? this.guid,
    name: name ?? this.name,
    welcomeMessage: welcomeMessage ?? this.welcomeMessage,
    host: host ?? this.host,
    port: port ?? this.port,
    verified: verified ?? this.verified,
    publicKey: publicKey.present ? publicKey.value : this.publicKey,
    sessionKey: sessionKey.present ? sessionKey.value : this.sessionKey,
    alias: alias.present ? alias.value : this.alias,
    autoAccept: autoAccept ?? this.autoAccept,
    firstSeen: firstSeen ?? this.firstSeen,
    lastSeen: lastSeen ?? this.lastSeen,
  );
  Peer copyWithCompanion(PeersCompanion data) {
    return Peer(
      id: data.id.present ? data.id.value : this.id,
      guid: data.guid.present ? data.guid.value : this.guid,
      name: data.name.present ? data.name.value : this.name,
      welcomeMessage: data.welcomeMessage.present
          ? data.welcomeMessage.value
          : this.welcomeMessage,
      host: data.host.present ? data.host.value : this.host,
      port: data.port.present ? data.port.value : this.port,
      verified: data.verified.present ? data.verified.value : this.verified,
      publicKey: data.publicKey.present ? data.publicKey.value : this.publicKey,
      sessionKey: data.sessionKey.present
          ? data.sessionKey.value
          : this.sessionKey,
      alias: data.alias.present ? data.alias.value : this.alias,
      autoAccept: data.autoAccept.present
          ? data.autoAccept.value
          : this.autoAccept,
      firstSeen: data.firstSeen.present ? data.firstSeen.value : this.firstSeen,
      lastSeen: data.lastSeen.present ? data.lastSeen.value : this.lastSeen,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Peer(')
          ..write('id: $id, ')
          ..write('guid: $guid, ')
          ..write('name: $name, ')
          ..write('welcomeMessage: $welcomeMessage, ')
          ..write('host: $host, ')
          ..write('port: $port, ')
          ..write('verified: $verified, ')
          ..write('publicKey: $publicKey, ')
          ..write('sessionKey: $sessionKey, ')
          ..write('alias: $alias, ')
          ..write('autoAccept: $autoAccept, ')
          ..write('firstSeen: $firstSeen, ')
          ..write('lastSeen: $lastSeen')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    guid,
    name,
    welcomeMessage,
    host,
    port,
    verified,
    publicKey,
    sessionKey,
    alias,
    autoAccept,
    firstSeen,
    lastSeen,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Peer &&
          other.id == this.id &&
          other.guid == this.guid &&
          other.name == this.name &&
          other.welcomeMessage == this.welcomeMessage &&
          other.host == this.host &&
          other.port == this.port &&
          other.verified == this.verified &&
          other.publicKey == this.publicKey &&
          other.sessionKey == this.sessionKey &&
          other.alias == this.alias &&
          other.autoAccept == this.autoAccept &&
          other.firstSeen == this.firstSeen &&
          other.lastSeen == this.lastSeen);
}

class PeersCompanion extends UpdateCompanion<Peer> {
  final Value<int> id;
  final Value<String> guid;
  final Value<String> name;
  final Value<String> welcomeMessage;
  final Value<String> host;
  final Value<int> port;
  final Value<bool> verified;
  final Value<String?> publicKey;
  final Value<String?> sessionKey;
  final Value<String?> alias;
  final Value<bool> autoAccept;
  final Value<DateTime> firstSeen;
  final Value<DateTime> lastSeen;
  const PeersCompanion({
    this.id = const Value.absent(),
    this.guid = const Value.absent(),
    this.name = const Value.absent(),
    this.welcomeMessage = const Value.absent(),
    this.host = const Value.absent(),
    this.port = const Value.absent(),
    this.verified = const Value.absent(),
    this.publicKey = const Value.absent(),
    this.sessionKey = const Value.absent(),
    this.alias = const Value.absent(),
    this.autoAccept = const Value.absent(),
    this.firstSeen = const Value.absent(),
    this.lastSeen = const Value.absent(),
  });
  PeersCompanion.insert({
    this.id = const Value.absent(),
    required String guid,
    required String name,
    this.welcomeMessage = const Value.absent(),
    required String host,
    required int port,
    this.verified = const Value.absent(),
    this.publicKey = const Value.absent(),
    this.sessionKey = const Value.absent(),
    this.alias = const Value.absent(),
    this.autoAccept = const Value.absent(),
    required DateTime firstSeen,
    required DateTime lastSeen,
  }) : guid = Value(guid),
       name = Value(name),
       host = Value(host),
       port = Value(port),
       firstSeen = Value(firstSeen),
       lastSeen = Value(lastSeen);
  static Insertable<Peer> custom({
    Expression<int>? id,
    Expression<String>? guid,
    Expression<String>? name,
    Expression<String>? welcomeMessage,
    Expression<String>? host,
    Expression<int>? port,
    Expression<bool>? verified,
    Expression<String>? publicKey,
    Expression<String>? sessionKey,
    Expression<String>? alias,
    Expression<bool>? autoAccept,
    Expression<DateTime>? firstSeen,
    Expression<DateTime>? lastSeen,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (guid != null) 'guid': guid,
      if (name != null) 'name': name,
      if (welcomeMessage != null) 'welcome_message': welcomeMessage,
      if (host != null) 'host': host,
      if (port != null) 'port': port,
      if (verified != null) 'verified': verified,
      if (publicKey != null) 'public_key': publicKey,
      if (sessionKey != null) 'session_key': sessionKey,
      if (alias != null) 'alias': alias,
      if (autoAccept != null) 'auto_accept': autoAccept,
      if (firstSeen != null) 'first_seen': firstSeen,
      if (lastSeen != null) 'last_seen': lastSeen,
    });
  }

  PeersCompanion copyWith({
    Value<int>? id,
    Value<String>? guid,
    Value<String>? name,
    Value<String>? welcomeMessage,
    Value<String>? host,
    Value<int>? port,
    Value<bool>? verified,
    Value<String?>? publicKey,
    Value<String?>? sessionKey,
    Value<String?>? alias,
    Value<bool>? autoAccept,
    Value<DateTime>? firstSeen,
    Value<DateTime>? lastSeen,
  }) {
    return PeersCompanion(
      id: id ?? this.id,
      guid: guid ?? this.guid,
      name: name ?? this.name,
      welcomeMessage: welcomeMessage ?? this.welcomeMessage,
      host: host ?? this.host,
      port: port ?? this.port,
      verified: verified ?? this.verified,
      publicKey: publicKey ?? this.publicKey,
      sessionKey: sessionKey ?? this.sessionKey,
      alias: alias ?? this.alias,
      autoAccept: autoAccept ?? this.autoAccept,
      firstSeen: firstSeen ?? this.firstSeen,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (guid.present) {
      map['guid'] = Variable<String>(guid.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (welcomeMessage.present) {
      map['welcome_message'] = Variable<String>(welcomeMessage.value);
    }
    if (host.present) {
      map['host'] = Variable<String>(host.value);
    }
    if (port.present) {
      map['port'] = Variable<int>(port.value);
    }
    if (verified.present) {
      map['verified'] = Variable<bool>(verified.value);
    }
    if (publicKey.present) {
      map['public_key'] = Variable<String>(publicKey.value);
    }
    if (sessionKey.present) {
      map['session_key'] = Variable<String>(sessionKey.value);
    }
    if (alias.present) {
      map['alias'] = Variable<String>(alias.value);
    }
    if (autoAccept.present) {
      map['auto_accept'] = Variable<bool>(autoAccept.value);
    }
    if (firstSeen.present) {
      map['first_seen'] = Variable<DateTime>(firstSeen.value);
    }
    if (lastSeen.present) {
      map['last_seen'] = Variable<DateTime>(lastSeen.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PeersCompanion(')
          ..write('id: $id, ')
          ..write('guid: $guid, ')
          ..write('name: $name, ')
          ..write('welcomeMessage: $welcomeMessage, ')
          ..write('host: $host, ')
          ..write('port: $port, ')
          ..write('verified: $verified, ')
          ..write('publicKey: $publicKey, ')
          ..write('sessionKey: $sessionKey, ')
          ..write('alias: $alias, ')
          ..write('autoAccept: $autoAccept, ')
          ..write('firstSeen: $firstSeen, ')
          ..write('lastSeen: $lastSeen')
          ..write(')'))
        .toString();
  }
}

class $ConversationsTable extends Conversations
    with TableInfo<$ConversationsTable, Conversation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ConversationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _peerIdMeta = const VerificationMeta('peerId');
  @override
  late final GeneratedColumn<int> peerId = GeneratedColumn<int>(
    'peer_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'UNIQUE REFERENCES peers (id)',
    ),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, peerId, createdAt, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'conversations';
  @override
  VerificationContext validateIntegrity(
    Insertable<Conversation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('peer_id')) {
      context.handle(
        _peerIdMeta,
        peerId.isAcceptableOrUnknown(data['peer_id']!, _peerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_peerIdMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Conversation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Conversation(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      peerId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}peer_id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ConversationsTable createAlias(String alias) {
    return $ConversationsTable(attachedDatabase, alias);
  }
}

class Conversation extends DataClass implements Insertable<Conversation> {
  final int id;
  final int peerId;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Conversation({
    required this.id,
    required this.peerId,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['peer_id'] = Variable<int>(peerId);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ConversationsCompanion toCompanion(bool nullToAbsent) {
    return ConversationsCompanion(
      id: Value(id),
      peerId: Value(peerId),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Conversation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Conversation(
      id: serializer.fromJson<int>(json['id']),
      peerId: serializer.fromJson<int>(json['peerId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'peerId': serializer.toJson<int>(peerId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Conversation copyWith({
    int? id,
    int? peerId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Conversation(
    id: id ?? this.id,
    peerId: peerId ?? this.peerId,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Conversation copyWithCompanion(ConversationsCompanion data) {
    return Conversation(
      id: data.id.present ? data.id.value : this.id,
      peerId: data.peerId.present ? data.peerId.value : this.peerId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Conversation(')
          ..write('id: $id, ')
          ..write('peerId: $peerId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, peerId, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Conversation &&
          other.id == this.id &&
          other.peerId == this.peerId &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ConversationsCompanion extends UpdateCompanion<Conversation> {
  final Value<int> id;
  final Value<int> peerId;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const ConversationsCompanion({
    this.id = const Value.absent(),
    this.peerId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  ConversationsCompanion.insert({
    this.id = const Value.absent(),
    required int peerId,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) : peerId = Value(peerId),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<Conversation> custom({
    Expression<int>? id,
    Expression<int>? peerId,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (peerId != null) 'peer_id': peerId,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  ConversationsCompanion copyWith({
    Value<int>? id,
    Value<int>? peerId,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
  }) {
    return ConversationsCompanion(
      id: id ?? this.id,
      peerId: peerId ?? this.peerId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (peerId.present) {
      map['peer_id'] = Variable<int>(peerId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ConversationsCompanion(')
          ..write('id: $id, ')
          ..write('peerId: $peerId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $MessagesTable extends Messages with TableInfo<$MessagesTable, Message> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _messageGuidMeta = const VerificationMeta(
    'messageGuid',
  );
  @override
  late final GeneratedColumn<String> messageGuid = GeneratedColumn<String>(
    'message_guid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _conversationIdMeta = const VerificationMeta(
    'conversationId',
  );
  @override
  late final GeneratedColumn<int> conversationId = GeneratedColumn<int>(
    'conversation_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES conversations (id)',
    ),
  );
  @override
  late final GeneratedColumnWithTypeConverter<MessageDirection, int> direction =
      GeneratedColumn<int>(
        'direction',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<MessageDirection>($MessagesTable.$converterdirection);
  @override
  late final GeneratedColumnWithTypeConverter<MessageStatus, int> status =
      GeneratedColumn<int>(
        'status',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<MessageStatus>($MessagesTable.$converterstatus);
  @override
  late final GeneratedColumnWithTypeConverter<MessageKind, int> kind =
      GeneratedColumn<int>(
        'kind',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
        defaultValue: Constant(MessageKind.text.index),
      ).withConverter<MessageKind>($MessagesTable.$converterkind);
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fileNameMeta = const VerificationMeta(
    'fileName',
  );
  @override
  late final GeneratedColumn<String> fileName = GeneratedColumn<String>(
    'file_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fileSizeMeta = const VerificationMeta(
    'fileSize',
  );
  @override
  late final GeneratedColumn<int> fileSize = GeneratedColumn<int>(
    'file_size',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _filePathMeta = const VerificationMeta(
    'filePath',
  );
  @override
  late final GeneratedColumn<String> filePath = GeneratedColumn<String>(
    'file_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deliveredAtMeta = const VerificationMeta(
    'deliveredAt',
  );
  @override
  late final GeneratedColumn<DateTime> deliveredAt = GeneratedColumn<DateTime>(
    'delivered_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _readAtMeta = const VerificationMeta('readAt');
  @override
  late final GeneratedColumn<DateTime> readAt = GeneratedColumn<DateTime>(
    'read_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    messageGuid,
    conversationId,
    direction,
    status,
    kind,
    body,
    fileName,
    fileSize,
    filePath,
    createdAt,
    deliveredAt,
    readAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'messages';
  @override
  VerificationContext validateIntegrity(
    Insertable<Message> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('message_guid')) {
      context.handle(
        _messageGuidMeta,
        messageGuid.isAcceptableOrUnknown(
          data['message_guid']!,
          _messageGuidMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_messageGuidMeta);
    }
    if (data.containsKey('conversation_id')) {
      context.handle(
        _conversationIdMeta,
        conversationId.isAcceptableOrUnknown(
          data['conversation_id']!,
          _conversationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_conversationIdMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    if (data.containsKey('file_name')) {
      context.handle(
        _fileNameMeta,
        fileName.isAcceptableOrUnknown(data['file_name']!, _fileNameMeta),
      );
    }
    if (data.containsKey('file_size')) {
      context.handle(
        _fileSizeMeta,
        fileSize.isAcceptableOrUnknown(data['file_size']!, _fileSizeMeta),
      );
    }
    if (data.containsKey('file_path')) {
      context.handle(
        _filePathMeta,
        filePath.isAcceptableOrUnknown(data['file_path']!, _filePathMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('delivered_at')) {
      context.handle(
        _deliveredAtMeta,
        deliveredAt.isAcceptableOrUnknown(
          data['delivered_at']!,
          _deliveredAtMeta,
        ),
      );
    }
    if (data.containsKey('read_at')) {
      context.handle(
        _readAtMeta,
        readAt.isAcceptableOrUnknown(data['read_at']!, _readAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Message map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Message(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      messageGuid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message_guid'],
      )!,
      conversationId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}conversation_id'],
      )!,
      direction: $MessagesTable.$converterdirection.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}direction'],
        )!,
      ),
      status: $MessagesTable.$converterstatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}status'],
        )!,
      ),
      kind: $MessagesTable.$converterkind.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}kind'],
        )!,
      ),
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
      fileName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_name'],
      ),
      fileSize: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}file_size'],
      ),
      filePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_path'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      deliveredAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}delivered_at'],
      ),
      readAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}read_at'],
      ),
    );
  }

  @override
  $MessagesTable createAlias(String alias) {
    return $MessagesTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<MessageDirection, int, int> $converterdirection =
      const EnumIndexConverter<MessageDirection>(MessageDirection.values);
  static JsonTypeConverter2<MessageStatus, int, int> $converterstatus =
      const EnumIndexConverter<MessageStatus>(MessageStatus.values);
  static JsonTypeConverter2<MessageKind, int, int> $converterkind =
      const EnumIndexConverter<MessageKind>(MessageKind.values);
}

class Message extends DataClass implements Insertable<Message> {
  final int id;

  /// Globalny identyfikator wiadomości, dzięki UNIQUE ponowne dostarczenie
  /// tej samej wiadomości (retry po zgubionym ACK-u) nie tworzy duplikatu.
  final String messageGuid;
  final int conversationId;
  final MessageDirection direction;
  final MessageStatus status;
  final MessageKind kind;
  final String body;

  /// Pola pliku (kind == file). [filePath]: u nadawcy ścieżka źródłowa,
  /// u odbiorcy miejsce zapisu.
  final String? fileName;
  final int? fileSize;
  final String? filePath;
  final DateTime createdAt;
  final DateTime? deliveredAt;
  final DateTime? readAt;
  const Message({
    required this.id,
    required this.messageGuid,
    required this.conversationId,
    required this.direction,
    required this.status,
    required this.kind,
    required this.body,
    this.fileName,
    this.fileSize,
    this.filePath,
    required this.createdAt,
    this.deliveredAt,
    this.readAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['message_guid'] = Variable<String>(messageGuid);
    map['conversation_id'] = Variable<int>(conversationId);
    {
      map['direction'] = Variable<int>(
        $MessagesTable.$converterdirection.toSql(direction),
      );
    }
    {
      map['status'] = Variable<int>(
        $MessagesTable.$converterstatus.toSql(status),
      );
    }
    {
      map['kind'] = Variable<int>($MessagesTable.$converterkind.toSql(kind));
    }
    map['body'] = Variable<String>(body);
    if (!nullToAbsent || fileName != null) {
      map['file_name'] = Variable<String>(fileName);
    }
    if (!nullToAbsent || fileSize != null) {
      map['file_size'] = Variable<int>(fileSize);
    }
    if (!nullToAbsent || filePath != null) {
      map['file_path'] = Variable<String>(filePath);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || deliveredAt != null) {
      map['delivered_at'] = Variable<DateTime>(deliveredAt);
    }
    if (!nullToAbsent || readAt != null) {
      map['read_at'] = Variable<DateTime>(readAt);
    }
    return map;
  }

  MessagesCompanion toCompanion(bool nullToAbsent) {
    return MessagesCompanion(
      id: Value(id),
      messageGuid: Value(messageGuid),
      conversationId: Value(conversationId),
      direction: Value(direction),
      status: Value(status),
      kind: Value(kind),
      body: Value(body),
      fileName: fileName == null && nullToAbsent
          ? const Value.absent()
          : Value(fileName),
      fileSize: fileSize == null && nullToAbsent
          ? const Value.absent()
          : Value(fileSize),
      filePath: filePath == null && nullToAbsent
          ? const Value.absent()
          : Value(filePath),
      createdAt: Value(createdAt),
      deliveredAt: deliveredAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deliveredAt),
      readAt: readAt == null && nullToAbsent
          ? const Value.absent()
          : Value(readAt),
    );
  }

  factory Message.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Message(
      id: serializer.fromJson<int>(json['id']),
      messageGuid: serializer.fromJson<String>(json['messageGuid']),
      conversationId: serializer.fromJson<int>(json['conversationId']),
      direction: $MessagesTable.$converterdirection.fromJson(
        serializer.fromJson<int>(json['direction']),
      ),
      status: $MessagesTable.$converterstatus.fromJson(
        serializer.fromJson<int>(json['status']),
      ),
      kind: $MessagesTable.$converterkind.fromJson(
        serializer.fromJson<int>(json['kind']),
      ),
      body: serializer.fromJson<String>(json['body']),
      fileName: serializer.fromJson<String?>(json['fileName']),
      fileSize: serializer.fromJson<int?>(json['fileSize']),
      filePath: serializer.fromJson<String?>(json['filePath']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      deliveredAt: serializer.fromJson<DateTime?>(json['deliveredAt']),
      readAt: serializer.fromJson<DateTime?>(json['readAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'messageGuid': serializer.toJson<String>(messageGuid),
      'conversationId': serializer.toJson<int>(conversationId),
      'direction': serializer.toJson<int>(
        $MessagesTable.$converterdirection.toJson(direction),
      ),
      'status': serializer.toJson<int>(
        $MessagesTable.$converterstatus.toJson(status),
      ),
      'kind': serializer.toJson<int>(
        $MessagesTable.$converterkind.toJson(kind),
      ),
      'body': serializer.toJson<String>(body),
      'fileName': serializer.toJson<String?>(fileName),
      'fileSize': serializer.toJson<int?>(fileSize),
      'filePath': serializer.toJson<String?>(filePath),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'deliveredAt': serializer.toJson<DateTime?>(deliveredAt),
      'readAt': serializer.toJson<DateTime?>(readAt),
    };
  }

  Message copyWith({
    int? id,
    String? messageGuid,
    int? conversationId,
    MessageDirection? direction,
    MessageStatus? status,
    MessageKind? kind,
    String? body,
    Value<String?> fileName = const Value.absent(),
    Value<int?> fileSize = const Value.absent(),
    Value<String?> filePath = const Value.absent(),
    DateTime? createdAt,
    Value<DateTime?> deliveredAt = const Value.absent(),
    Value<DateTime?> readAt = const Value.absent(),
  }) => Message(
    id: id ?? this.id,
    messageGuid: messageGuid ?? this.messageGuid,
    conversationId: conversationId ?? this.conversationId,
    direction: direction ?? this.direction,
    status: status ?? this.status,
    kind: kind ?? this.kind,
    body: body ?? this.body,
    fileName: fileName.present ? fileName.value : this.fileName,
    fileSize: fileSize.present ? fileSize.value : this.fileSize,
    filePath: filePath.present ? filePath.value : this.filePath,
    createdAt: createdAt ?? this.createdAt,
    deliveredAt: deliveredAt.present ? deliveredAt.value : this.deliveredAt,
    readAt: readAt.present ? readAt.value : this.readAt,
  );
  Message copyWithCompanion(MessagesCompanion data) {
    return Message(
      id: data.id.present ? data.id.value : this.id,
      messageGuid: data.messageGuid.present
          ? data.messageGuid.value
          : this.messageGuid,
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      direction: data.direction.present ? data.direction.value : this.direction,
      status: data.status.present ? data.status.value : this.status,
      kind: data.kind.present ? data.kind.value : this.kind,
      body: data.body.present ? data.body.value : this.body,
      fileName: data.fileName.present ? data.fileName.value : this.fileName,
      fileSize: data.fileSize.present ? data.fileSize.value : this.fileSize,
      filePath: data.filePath.present ? data.filePath.value : this.filePath,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      deliveredAt: data.deliveredAt.present
          ? data.deliveredAt.value
          : this.deliveredAt,
      readAt: data.readAt.present ? data.readAt.value : this.readAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Message(')
          ..write('id: $id, ')
          ..write('messageGuid: $messageGuid, ')
          ..write('conversationId: $conversationId, ')
          ..write('direction: $direction, ')
          ..write('status: $status, ')
          ..write('kind: $kind, ')
          ..write('body: $body, ')
          ..write('fileName: $fileName, ')
          ..write('fileSize: $fileSize, ')
          ..write('filePath: $filePath, ')
          ..write('createdAt: $createdAt, ')
          ..write('deliveredAt: $deliveredAt, ')
          ..write('readAt: $readAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    messageGuid,
    conversationId,
    direction,
    status,
    kind,
    body,
    fileName,
    fileSize,
    filePath,
    createdAt,
    deliveredAt,
    readAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Message &&
          other.id == this.id &&
          other.messageGuid == this.messageGuid &&
          other.conversationId == this.conversationId &&
          other.direction == this.direction &&
          other.status == this.status &&
          other.kind == this.kind &&
          other.body == this.body &&
          other.fileName == this.fileName &&
          other.fileSize == this.fileSize &&
          other.filePath == this.filePath &&
          other.createdAt == this.createdAt &&
          other.deliveredAt == this.deliveredAt &&
          other.readAt == this.readAt);
}

class MessagesCompanion extends UpdateCompanion<Message> {
  final Value<int> id;
  final Value<String> messageGuid;
  final Value<int> conversationId;
  final Value<MessageDirection> direction;
  final Value<MessageStatus> status;
  final Value<MessageKind> kind;
  final Value<String> body;
  final Value<String?> fileName;
  final Value<int?> fileSize;
  final Value<String?> filePath;
  final Value<DateTime> createdAt;
  final Value<DateTime?> deliveredAt;
  final Value<DateTime?> readAt;
  const MessagesCompanion({
    this.id = const Value.absent(),
    this.messageGuid = const Value.absent(),
    this.conversationId = const Value.absent(),
    this.direction = const Value.absent(),
    this.status = const Value.absent(),
    this.kind = const Value.absent(),
    this.body = const Value.absent(),
    this.fileName = const Value.absent(),
    this.fileSize = const Value.absent(),
    this.filePath = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.deliveredAt = const Value.absent(),
    this.readAt = const Value.absent(),
  });
  MessagesCompanion.insert({
    this.id = const Value.absent(),
    required String messageGuid,
    required int conversationId,
    required MessageDirection direction,
    required MessageStatus status,
    this.kind = const Value.absent(),
    required String body,
    this.fileName = const Value.absent(),
    this.fileSize = const Value.absent(),
    this.filePath = const Value.absent(),
    required DateTime createdAt,
    this.deliveredAt = const Value.absent(),
    this.readAt = const Value.absent(),
  }) : messageGuid = Value(messageGuid),
       conversationId = Value(conversationId),
       direction = Value(direction),
       status = Value(status),
       body = Value(body),
       createdAt = Value(createdAt);
  static Insertable<Message> custom({
    Expression<int>? id,
    Expression<String>? messageGuid,
    Expression<int>? conversationId,
    Expression<int>? direction,
    Expression<int>? status,
    Expression<int>? kind,
    Expression<String>? body,
    Expression<String>? fileName,
    Expression<int>? fileSize,
    Expression<String>? filePath,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? deliveredAt,
    Expression<DateTime>? readAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (messageGuid != null) 'message_guid': messageGuid,
      if (conversationId != null) 'conversation_id': conversationId,
      if (direction != null) 'direction': direction,
      if (status != null) 'status': status,
      if (kind != null) 'kind': kind,
      if (body != null) 'body': body,
      if (fileName != null) 'file_name': fileName,
      if (fileSize != null) 'file_size': fileSize,
      if (filePath != null) 'file_path': filePath,
      if (createdAt != null) 'created_at': createdAt,
      if (deliveredAt != null) 'delivered_at': deliveredAt,
      if (readAt != null) 'read_at': readAt,
    });
  }

  MessagesCompanion copyWith({
    Value<int>? id,
    Value<String>? messageGuid,
    Value<int>? conversationId,
    Value<MessageDirection>? direction,
    Value<MessageStatus>? status,
    Value<MessageKind>? kind,
    Value<String>? body,
    Value<String?>? fileName,
    Value<int?>? fileSize,
    Value<String?>? filePath,
    Value<DateTime>? createdAt,
    Value<DateTime?>? deliveredAt,
    Value<DateTime?>? readAt,
  }) {
    return MessagesCompanion(
      id: id ?? this.id,
      messageGuid: messageGuid ?? this.messageGuid,
      conversationId: conversationId ?? this.conversationId,
      direction: direction ?? this.direction,
      status: status ?? this.status,
      kind: kind ?? this.kind,
      body: body ?? this.body,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      filePath: filePath ?? this.filePath,
      createdAt: createdAt ?? this.createdAt,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      readAt: readAt ?? this.readAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (messageGuid.present) {
      map['message_guid'] = Variable<String>(messageGuid.value);
    }
    if (conversationId.present) {
      map['conversation_id'] = Variable<int>(conversationId.value);
    }
    if (direction.present) {
      map['direction'] = Variable<int>(
        $MessagesTable.$converterdirection.toSql(direction.value),
      );
    }
    if (status.present) {
      map['status'] = Variable<int>(
        $MessagesTable.$converterstatus.toSql(status.value),
      );
    }
    if (kind.present) {
      map['kind'] = Variable<int>(
        $MessagesTable.$converterkind.toSql(kind.value),
      );
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (fileName.present) {
      map['file_name'] = Variable<String>(fileName.value);
    }
    if (fileSize.present) {
      map['file_size'] = Variable<int>(fileSize.value);
    }
    if (filePath.present) {
      map['file_path'] = Variable<String>(filePath.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (deliveredAt.present) {
      map['delivered_at'] = Variable<DateTime>(deliveredAt.value);
    }
    if (readAt.present) {
      map['read_at'] = Variable<DateTime>(readAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MessagesCompanion(')
          ..write('id: $id, ')
          ..write('messageGuid: $messageGuid, ')
          ..write('conversationId: $conversationId, ')
          ..write('direction: $direction, ')
          ..write('status: $status, ')
          ..write('kind: $kind, ')
          ..write('body: $body, ')
          ..write('fileName: $fileName, ')
          ..write('fileSize: $fileSize, ')
          ..write('filePath: $filePath, ')
          ..write('createdAt: $createdAt, ')
          ..write('deliveredAt: $deliveredAt, ')
          ..write('readAt: $readAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$ChattDb extends GeneratedDatabase {
  _$ChattDb(QueryExecutor e) : super(e);
  $ChattDbManager get managers => $ChattDbManager(this);
  late final $SettingsTable settings = $SettingsTable(this);
  late final $PeersTable peers = $PeersTable(this);
  late final $ConversationsTable conversations = $ConversationsTable(this);
  late final $MessagesTable messages = $MessagesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    settings,
    peers,
    conversations,
    messages,
  ];
}

typedef $$SettingsTableCreateCompanionBuilder = SettingsCompanion Function({
  Value<int> id,
  required String deviceGuid,
  Value<String> identityKey,
  required String nickname,
  Value<String> welcomeMessage,
  Value<AppTheme> theme,
  Value<AppLanguage> language,
  Value<int> tcpPort,
  Value<int> background,
  Value<int> retentionDays,
  Value<bool> updateChecks,
  Value<DateTime?> lastUpdateCheck,
});
typedef $$SettingsTableUpdateCompanionBuilder = SettingsCompanion Function({
  Value<int> id,
  Value<String> deviceGuid,
  Value<String> identityKey,
  Value<String> nickname,
  Value<String> welcomeMessage,
  Value<AppTheme> theme,
  Value<AppLanguage> language,
  Value<int> tcpPort,
  Value<int> background,
  Value<int> retentionDays,
  Value<bool> updateChecks,
  Value<DateTime?> lastUpdateCheck,
});

class $$SettingsTableFilterComposer
    extends Composer<_$ChattDb, $SettingsTable> {
  $$SettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceGuid => $composableBuilder(
    column: $table.deviceGuid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get identityKey => $composableBuilder(
    column: $table.identityKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nickname => $composableBuilder(
    column: $table.nickname,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get welcomeMessage => $composableBuilder(
    column: $table.welcomeMessage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<AppTheme, AppTheme, int> get theme =>
      $composableBuilder(
        column: $table.theme,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<AppLanguage, AppLanguage, int> get language =>
      $composableBuilder(
        column: $table.language,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<int> get tcpPort => $composableBuilder(
    column: $table.tcpPort,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get background => $composableBuilder(
    column: $table.background,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get retentionDays => $composableBuilder(
    column: $table.retentionDays,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get updateChecks => $composableBuilder(
    column: $table.updateChecks,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastUpdateCheck => $composableBuilder(
    column: $table.lastUpdateCheck,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SettingsTableOrderingComposer
    extends Composer<_$ChattDb, $SettingsTable> {
  $$SettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceGuid => $composableBuilder(
    column: $table.deviceGuid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get identityKey => $composableBuilder(
    column: $table.identityKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nickname => $composableBuilder(
    column: $table.nickname,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get welcomeMessage => $composableBuilder(
    column: $table.welcomeMessage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get theme => $composableBuilder(
    column: $table.theme,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get language => $composableBuilder(
    column: $table.language,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get tcpPort => $composableBuilder(
    column: $table.tcpPort,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get background => $composableBuilder(
    column: $table.background,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get retentionDays => $composableBuilder(
    column: $table.retentionDays,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get updateChecks => $composableBuilder(
    column: $table.updateChecks,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastUpdateCheck => $composableBuilder(
    column: $table.lastUpdateCheck,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SettingsTableAnnotationComposer
    extends Composer<_$ChattDb, $SettingsTable> {
  $$SettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get deviceGuid => $composableBuilder(
    column: $table.deviceGuid,
    builder: (column) => column,
  );

  GeneratedColumn<String> get identityKey => $composableBuilder(
    column: $table.identityKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get nickname =>
      $composableBuilder(column: $table.nickname, builder: (column) => column);

  GeneratedColumn<String> get welcomeMessage => $composableBuilder(
    column: $table.welcomeMessage,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<AppTheme, int> get theme =>
      $composableBuilder(column: $table.theme, builder: (column) => column);

  GeneratedColumnWithTypeConverter<AppLanguage, int> get language =>
      $composableBuilder(column: $table.language, builder: (column) => column);

  GeneratedColumn<int> get tcpPort =>
      $composableBuilder(column: $table.tcpPort, builder: (column) => column);

  GeneratedColumn<int> get background => $composableBuilder(
    column: $table.background,
    builder: (column) => column,
  );

  GeneratedColumn<int> get retentionDays => $composableBuilder(
    column: $table.retentionDays,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get updateChecks => $composableBuilder(
    column: $table.updateChecks,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastUpdateCheck => $composableBuilder(
    column: $table.lastUpdateCheck,
    builder: (column) => column,
  );
}

class $$SettingsTableTableManager
    extends
        RootTableManager<
          _$ChattDb,
          $SettingsTable,
          Setting,
          $$SettingsTableFilterComposer,
          $$SettingsTableOrderingComposer,
          $$SettingsTableAnnotationComposer,
          $$SettingsTableCreateCompanionBuilder,
          $$SettingsTableUpdateCompanionBuilder,
          (Setting, BaseReferences<_$ChattDb, $SettingsTable, Setting>),
          Setting,
          PrefetchHooks Function()
        > {
  $$SettingsTableTableManager(_$ChattDb db, $SettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> deviceGuid = const Value.absent(),
                Value<String> identityKey = const Value.absent(),
                Value<String> nickname = const Value.absent(),
                Value<String> welcomeMessage = const Value.absent(),
                Value<AppTheme> theme = const Value.absent(),
                Value<AppLanguage> language = const Value.absent(),
                Value<int> tcpPort = const Value.absent(),
                Value<int> background = const Value.absent(),
                Value<int> retentionDays = const Value.absent(),
                Value<bool> updateChecks = const Value.absent(),
                Value<DateTime?> lastUpdateCheck = const Value.absent(),
              }) => SettingsCompanion(
                id: id,
                deviceGuid: deviceGuid,
                identityKey: identityKey,
                nickname: nickname,
                welcomeMessage: welcomeMessage,
                theme: theme,
                language: language,
                tcpPort: tcpPort,
                background: background,
                retentionDays: retentionDays,
                updateChecks: updateChecks,
                lastUpdateCheck: lastUpdateCheck,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String deviceGuid,
                Value<String> identityKey = const Value.absent(),
                required String nickname,
                Value<String> welcomeMessage = const Value.absent(),
                Value<AppTheme> theme = const Value.absent(),
                Value<AppLanguage> language = const Value.absent(),
                Value<int> tcpPort = const Value.absent(),
                Value<int> background = const Value.absent(),
                Value<int> retentionDays = const Value.absent(),
                Value<bool> updateChecks = const Value.absent(),
                Value<DateTime?> lastUpdateCheck = const Value.absent(),
              }) => SettingsCompanion.insert(
                id: id,
                deviceGuid: deviceGuid,
                identityKey: identityKey,
                nickname: nickname,
                welcomeMessage: welcomeMessage,
                theme: theme,
                language: language,
                tcpPort: tcpPort,
                background: background,
                retentionDays: retentionDays,
                updateChecks: updateChecks,
                lastUpdateCheck: lastUpdateCheck,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$ChattDb,
      $SettingsTable,
      Setting,
      $$SettingsTableFilterComposer,
      $$SettingsTableOrderingComposer,
      $$SettingsTableAnnotationComposer,
      $$SettingsTableCreateCompanionBuilder,
      $$SettingsTableUpdateCompanionBuilder,
      (Setting, BaseReferences<_$ChattDb, $SettingsTable, Setting>),
      Setting,
      PrefetchHooks Function()
    >;
typedef $$PeersTableCreateCompanionBuilder = PeersCompanion Function({
  Value<int> id,
  required String guid,
  required String name,
  Value<String> welcomeMessage,
  required String host,
  required int port,
  Value<bool> verified,
  Value<String?> publicKey,
  Value<String?> sessionKey,
  Value<String?> alias,
  Value<bool> autoAccept,
  required DateTime firstSeen,
  required DateTime lastSeen,
});
typedef $$PeersTableUpdateCompanionBuilder = PeersCompanion Function({
  Value<int> id,
  Value<String> guid,
  Value<String> name,
  Value<String> welcomeMessage,
  Value<String> host,
  Value<int> port,
  Value<bool> verified,
  Value<String?> publicKey,
  Value<String?> sessionKey,
  Value<String?> alias,
  Value<bool> autoAccept,
  Value<DateTime> firstSeen,
  Value<DateTime> lastSeen,
});

final class $$PeersTableReferences
    extends BaseReferences<_$ChattDb, $PeersTable, Peer> {
  $$PeersTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$ConversationsTable, List<Conversation>>
  _conversationsRefsTable(_$ChattDb db) => MultiTypedResultKey.fromTable(
    db.conversations,
    aliasName: 'peers__id__conversations__peer_id',
  );

  $$ConversationsTableProcessedTableManager get conversationsRefs {
    final manager = $$ConversationsTableTableManager(
      $_db,
      $_db.conversations,
    ).filter((f) => f.peerId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_conversationsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$PeersTableFilterComposer extends Composer<_$ChattDb, $PeersTable> {
  $$PeersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get guid => $composableBuilder(
    column: $table.guid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get welcomeMessage => $composableBuilder(
    column: $table.welcomeMessage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get host => $composableBuilder(
    column: $table.host,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get port => $composableBuilder(
    column: $table.port,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get verified => $composableBuilder(
    column: $table.verified,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get publicKey => $composableBuilder(
    column: $table.publicKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sessionKey => $composableBuilder(
    column: $table.sessionKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get alias => $composableBuilder(
    column: $table.alias,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get autoAccept => $composableBuilder(
    column: $table.autoAccept,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get firstSeen => $composableBuilder(
    column: $table.firstSeen,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastSeen => $composableBuilder(
    column: $table.lastSeen,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> conversationsRefs(
    Expression<bool> Function($$ConversationsTableFilterComposer f) f,
  ) {
    final $$ConversationsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.conversations,
      getReferencedColumn: (t) => t.peerId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ConversationsTableFilterComposer(
            $db: $db,
            $table: $db.conversations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$PeersTableOrderingComposer extends Composer<_$ChattDb, $PeersTable> {
  $$PeersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get guid => $composableBuilder(
    column: $table.guid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get welcomeMessage => $composableBuilder(
    column: $table.welcomeMessage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get host => $composableBuilder(
    column: $table.host,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get port => $composableBuilder(
    column: $table.port,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get verified => $composableBuilder(
    column: $table.verified,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get publicKey => $composableBuilder(
    column: $table.publicKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sessionKey => $composableBuilder(
    column: $table.sessionKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get alias => $composableBuilder(
    column: $table.alias,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get autoAccept => $composableBuilder(
    column: $table.autoAccept,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get firstSeen => $composableBuilder(
    column: $table.firstSeen,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastSeen => $composableBuilder(
    column: $table.lastSeen,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PeersTableAnnotationComposer extends Composer<_$ChattDb, $PeersTable> {
  $$PeersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get guid =>
      $composableBuilder(column: $table.guid, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get welcomeMessage => $composableBuilder(
    column: $table.welcomeMessage,
    builder: (column) => column,
  );

  GeneratedColumn<String> get host =>
      $composableBuilder(column: $table.host, builder: (column) => column);

  GeneratedColumn<int> get port =>
      $composableBuilder(column: $table.port, builder: (column) => column);

  GeneratedColumn<bool> get verified =>
      $composableBuilder(column: $table.verified, builder: (column) => column);

  GeneratedColumn<String> get publicKey =>
      $composableBuilder(column: $table.publicKey, builder: (column) => column);

  GeneratedColumn<String> get sessionKey => $composableBuilder(
    column: $table.sessionKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get alias =>
      $composableBuilder(column: $table.alias, builder: (column) => column);

  GeneratedColumn<bool> get autoAccept => $composableBuilder(
    column: $table.autoAccept,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get firstSeen =>
      $composableBuilder(column: $table.firstSeen, builder: (column) => column);

  GeneratedColumn<DateTime> get lastSeen =>
      $composableBuilder(column: $table.lastSeen, builder: (column) => column);

  Expression<T> conversationsRefs<T extends Object>(
    Expression<T> Function($$ConversationsTableAnnotationComposer a) f,
  ) {
    final $$ConversationsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.conversations,
      getReferencedColumn: (t) => t.peerId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ConversationsTableAnnotationComposer(
            $db: $db,
            $table: $db.conversations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$PeersTableTableManager
    extends
        RootTableManager<
          _$ChattDb,
          $PeersTable,
          Peer,
          $$PeersTableFilterComposer,
          $$PeersTableOrderingComposer,
          $$PeersTableAnnotationComposer,
          $$PeersTableCreateCompanionBuilder,
          $$PeersTableUpdateCompanionBuilder,
          (Peer, $$PeersTableReferences),
          Peer,
          PrefetchHooks Function({bool conversationsRefs})
        > {
  $$PeersTableTableManager(_$ChattDb db, $PeersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PeersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PeersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PeersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> guid = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> welcomeMessage = const Value.absent(),
                Value<String> host = const Value.absent(),
                Value<int> port = const Value.absent(),
                Value<bool> verified = const Value.absent(),
                Value<String?> publicKey = const Value.absent(),
                Value<String?> sessionKey = const Value.absent(),
                Value<String?> alias = const Value.absent(),
                Value<bool> autoAccept = const Value.absent(),
                Value<DateTime> firstSeen = const Value.absent(),
                Value<DateTime> lastSeen = const Value.absent(),
              }) => PeersCompanion(
                id: id,
                guid: guid,
                name: name,
                welcomeMessage: welcomeMessage,
                host: host,
                port: port,
                verified: verified,
                publicKey: publicKey,
                sessionKey: sessionKey,
                alias: alias,
                autoAccept: autoAccept,
                firstSeen: firstSeen,
                lastSeen: lastSeen,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String guid,
                required String name,
                Value<String> welcomeMessage = const Value.absent(),
                required String host,
                required int port,
                Value<bool> verified = const Value.absent(),
                Value<String?> publicKey = const Value.absent(),
                Value<String?> sessionKey = const Value.absent(),
                Value<String?> alias = const Value.absent(),
                Value<bool> autoAccept = const Value.absent(),
                required DateTime firstSeen,
                required DateTime lastSeen,
              }) => PeersCompanion.insert(
                id: id,
                guid: guid,
                name: name,
                welcomeMessage: welcomeMessage,
                host: host,
                port: port,
                verified: verified,
                publicKey: publicKey,
                sessionKey: sessionKey,
                alias: alias,
                autoAccept: autoAccept,
                firstSeen: firstSeen,
                lastSeen: lastSeen,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$PeersTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback: ({conversationsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (conversationsRefs) db.conversations,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (conversationsRefs)
                    await $_getPrefetchedData<Peer, $PeersTable, Conversation>(
                      currentTable: table,
                      referencedTable: $$PeersTableReferences
                          ._conversationsRefsTable(db),
                      managerFromTypedResult: (p0) => $$PeersTableReferences(
                        db,
                        table,
                        p0,
                      ).conversationsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.peerId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$PeersTableProcessedTableManager =
    ProcessedTableManager<
      _$ChattDb,
      $PeersTable,
      Peer,
      $$PeersTableFilterComposer,
      $$PeersTableOrderingComposer,
      $$PeersTableAnnotationComposer,
      $$PeersTableCreateCompanionBuilder,
      $$PeersTableUpdateCompanionBuilder,
      (Peer, $$PeersTableReferences),
      Peer,
      PrefetchHooks Function({bool conversationsRefs})
    >;
typedef $$ConversationsTableCreateCompanionBuilder =
    ConversationsCompanion Function({
      Value<int> id,
      required int peerId,
      required DateTime createdAt,
      required DateTime updatedAt,
    });
typedef $$ConversationsTableUpdateCompanionBuilder =
    ConversationsCompanion Function({
      Value<int> id,
      Value<int> peerId,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });

final class $$ConversationsTableReferences
    extends BaseReferences<_$ChattDb, $ConversationsTable, Conversation> {
  $$ConversationsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $PeersTable _peerIdTable(_$ChattDb db) =>
      db.peers.createAlias('conversations__peer_id__peers__id');

  $$PeersTableProcessedTableManager get peerId {
    final $_column = $_itemColumn<int>('peer_id')!;

    final manager = $$PeersTableTableManager(
      $_db,
      $_db.peers,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_peerIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$MessagesTable, List<Message>> _messagesRefsTable(
    _$ChattDb db,
  ) => MultiTypedResultKey.fromTable(
    db.messages,
    aliasName: 'conversations__id__messages__conversation_id',
  );

  $$MessagesTableProcessedTableManager get messagesRefs {
    final manager = $$MessagesTableTableManager(
      $_db,
      $_db.messages,
    ).filter((f) => f.conversationId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_messagesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ConversationsTableFilterComposer
    extends Composer<_$ChattDb, $ConversationsTable> {
  $$ConversationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$PeersTableFilterComposer get peerId {
    final $$PeersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.peerId,
      referencedTable: $db.peers,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PeersTableFilterComposer(
            $db: $db,
            $table: $db.peers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> messagesRefs(
    Expression<bool> Function($$MessagesTableFilterComposer f) f,
  ) {
    final $$MessagesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.messages,
      getReferencedColumn: (t) => t.conversationId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessagesTableFilterComposer(
            $db: $db,
            $table: $db.messages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ConversationsTableOrderingComposer
    extends Composer<_$ChattDb, $ConversationsTable> {
  $$ConversationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$PeersTableOrderingComposer get peerId {
    final $$PeersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.peerId,
      referencedTable: $db.peers,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PeersTableOrderingComposer(
            $db: $db,
            $table: $db.peers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ConversationsTableAnnotationComposer
    extends Composer<_$ChattDb, $ConversationsTable> {
  $$ConversationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$PeersTableAnnotationComposer get peerId {
    final $$PeersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.peerId,
      referencedTable: $db.peers,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PeersTableAnnotationComposer(
            $db: $db,
            $table: $db.peers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> messagesRefs<T extends Object>(
    Expression<T> Function($$MessagesTableAnnotationComposer a) f,
  ) {
    final $$MessagesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.messages,
      getReferencedColumn: (t) => t.conversationId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessagesTableAnnotationComposer(
            $db: $db,
            $table: $db.messages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ConversationsTableTableManager
    extends
        RootTableManager<
          _$ChattDb,
          $ConversationsTable,
          Conversation,
          $$ConversationsTableFilterComposer,
          $$ConversationsTableOrderingComposer,
          $$ConversationsTableAnnotationComposer,
          $$ConversationsTableCreateCompanionBuilder,
          $$ConversationsTableUpdateCompanionBuilder,
          (Conversation, $$ConversationsTableReferences),
          Conversation,
          PrefetchHooks Function({bool peerId, bool messagesRefs})
        > {
  $$ConversationsTableTableManager(_$ChattDb db, $ConversationsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ConversationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ConversationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ConversationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> peerId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => ConversationsCompanion(
                id: id,
                peerId: peerId,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int peerId,
                required DateTime createdAt,
                required DateTime updatedAt,
              }) => ConversationsCompanion.insert(
                id: id,
                peerId: peerId,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ConversationsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({peerId = false, messagesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (messagesRefs) db.messages],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (peerId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.peerId,
                        referencedTable: $$ConversationsTableReferences
                            ._peerIdTable(db),
                        referencedColumn: $$ConversationsTableReferences
                            ._peerIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [
                  if (messagesRefs)
                    await $_getPrefetchedData<
                      Conversation,
                      $ConversationsTable,
                      Message
                    >(
                      currentTable: table,
                      referencedTable: $$ConversationsTableReferences
                          ._messagesRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$ConversationsTableReferences(
                            db,
                            table,
                            p0,
                          ).messagesRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where(
                            (e) => e.conversationId == item.id,
                          ),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$ConversationsTableProcessedTableManager =
    ProcessedTableManager<
      _$ChattDb,
      $ConversationsTable,
      Conversation,
      $$ConversationsTableFilterComposer,
      $$ConversationsTableOrderingComposer,
      $$ConversationsTableAnnotationComposer,
      $$ConversationsTableCreateCompanionBuilder,
      $$ConversationsTableUpdateCompanionBuilder,
      (Conversation, $$ConversationsTableReferences),
      Conversation,
      PrefetchHooks Function({bool peerId, bool messagesRefs})
    >;
typedef $$MessagesTableCreateCompanionBuilder = MessagesCompanion Function({
  Value<int> id,
  required String messageGuid,
  required int conversationId,
  required MessageDirection direction,
  required MessageStatus status,
  Value<MessageKind> kind,
  required String body,
  Value<String?> fileName,
  Value<int?> fileSize,
  Value<String?> filePath,
  required DateTime createdAt,
  Value<DateTime?> deliveredAt,
  Value<DateTime?> readAt,
});
typedef $$MessagesTableUpdateCompanionBuilder = MessagesCompanion Function({
  Value<int> id,
  Value<String> messageGuid,
  Value<int> conversationId,
  Value<MessageDirection> direction,
  Value<MessageStatus> status,
  Value<MessageKind> kind,
  Value<String> body,
  Value<String?> fileName,
  Value<int?> fileSize,
  Value<String?> filePath,
  Value<DateTime> createdAt,
  Value<DateTime?> deliveredAt,
  Value<DateTime?> readAt,
});

final class $$MessagesTableReferences
    extends BaseReferences<_$ChattDb, $MessagesTable, Message> {
  $$MessagesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ConversationsTable _conversationIdTable(_$ChattDb db) => db
      .conversations
      .createAlias('messages__conversation_id__conversations__id');

  $$ConversationsTableProcessedTableManager get conversationId {
    final $_column = $_itemColumn<int>('conversation_id')!;

    final manager = $$ConversationsTableTableManager(
      $_db,
      $_db.conversations,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_conversationIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$MessagesTableFilterComposer
    extends Composer<_$ChattDb, $MessagesTable> {
  $$MessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get messageGuid => $composableBuilder(
    column: $table.messageGuid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<MessageDirection, MessageDirection, int>
  get direction => $composableBuilder(
    column: $table.direction,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<MessageStatus, MessageStatus, int>
  get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<MessageKind, MessageKind, int> get kind =>
      $composableBuilder(
        column: $table.kind,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fileSize => $composableBuilder(
    column: $table.fileSize,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deliveredAt => $composableBuilder(
    column: $table.deliveredAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get readAt => $composableBuilder(
    column: $table.readAt,
    builder: (column) => ColumnFilters(column),
  );

  $$ConversationsTableFilterComposer get conversationId {
    final $$ConversationsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.conversationId,
      referencedTable: $db.conversations,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ConversationsTableFilterComposer(
            $db: $db,
            $table: $db.conversations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MessagesTableOrderingComposer
    extends Composer<_$ChattDb, $MessagesTable> {
  $$MessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get messageGuid => $composableBuilder(
    column: $table.messageGuid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get direction => $composableBuilder(
    column: $table.direction,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fileSize => $composableBuilder(
    column: $table.fileSize,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deliveredAt => $composableBuilder(
    column: $table.deliveredAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get readAt => $composableBuilder(
    column: $table.readAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$ConversationsTableOrderingComposer get conversationId {
    final $$ConversationsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.conversationId,
      referencedTable: $db.conversations,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ConversationsTableOrderingComposer(
            $db: $db,
            $table: $db.conversations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MessagesTableAnnotationComposer
    extends Composer<_$ChattDb, $MessagesTable> {
  $$MessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get messageGuid => $composableBuilder(
    column: $table.messageGuid,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<MessageDirection, int> get direction =>
      $composableBuilder(column: $table.direction, builder: (column) => column);

  GeneratedColumnWithTypeConverter<MessageStatus, int> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumnWithTypeConverter<MessageKind, int> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<String> get fileName =>
      $composableBuilder(column: $table.fileName, builder: (column) => column);

  GeneratedColumn<int> get fileSize =>
      $composableBuilder(column: $table.fileSize, builder: (column) => column);

  GeneratedColumn<String> get filePath =>
      $composableBuilder(column: $table.filePath, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deliveredAt => $composableBuilder(
    column: $table.deliveredAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get readAt =>
      $composableBuilder(column: $table.readAt, builder: (column) => column);

  $$ConversationsTableAnnotationComposer get conversationId {
    final $$ConversationsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.conversationId,
      referencedTable: $db.conversations,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ConversationsTableAnnotationComposer(
            $db: $db,
            $table: $db.conversations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MessagesTableTableManager
    extends
        RootTableManager<
          _$ChattDb,
          $MessagesTable,
          Message,
          $$MessagesTableFilterComposer,
          $$MessagesTableOrderingComposer,
          $$MessagesTableAnnotationComposer,
          $$MessagesTableCreateCompanionBuilder,
          $$MessagesTableUpdateCompanionBuilder,
          (Message, $$MessagesTableReferences),
          Message,
          PrefetchHooks Function({bool conversationId})
        > {
  $$MessagesTableTableManager(_$ChattDb db, $MessagesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> messageGuid = const Value.absent(),
                Value<int> conversationId = const Value.absent(),
                Value<MessageDirection> direction = const Value.absent(),
                Value<MessageStatus> status = const Value.absent(),
                Value<MessageKind> kind = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<String?> fileName = const Value.absent(),
                Value<int?> fileSize = const Value.absent(),
                Value<String?> filePath = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime?> deliveredAt = const Value.absent(),
                Value<DateTime?> readAt = const Value.absent(),
              }) => MessagesCompanion(
                id: id,
                messageGuid: messageGuid,
                conversationId: conversationId,
                direction: direction,
                status: status,
                kind: kind,
                body: body,
                fileName: fileName,
                fileSize: fileSize,
                filePath: filePath,
                createdAt: createdAt,
                deliveredAt: deliveredAt,
                readAt: readAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String messageGuid,
                required int conversationId,
                required MessageDirection direction,
                required MessageStatus status,
                Value<MessageKind> kind = const Value.absent(),
                required String body,
                Value<String?> fileName = const Value.absent(),
                Value<int?> fileSize = const Value.absent(),
                Value<String?> filePath = const Value.absent(),
                required DateTime createdAt,
                Value<DateTime?> deliveredAt = const Value.absent(),
                Value<DateTime?> readAt = const Value.absent(),
              }) => MessagesCompanion.insert(
                id: id,
                messageGuid: messageGuid,
                conversationId: conversationId,
                direction: direction,
                status: status,
                kind: kind,
                body: body,
                fileName: fileName,
                fileSize: fileSize,
                filePath: filePath,
                createdAt: createdAt,
                deliveredAt: deliveredAt,
                readAt: readAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$MessagesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({conversationId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (conversationId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.conversationId,
                        referencedTable: $$MessagesTableReferences
                            ._conversationIdTable(db),
                        referencedColumn: $$MessagesTableReferences
                            ._conversationIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$MessagesTableProcessedTableManager =
    ProcessedTableManager<
      _$ChattDb,
      $MessagesTable,
      Message,
      $$MessagesTableFilterComposer,
      $$MessagesTableOrderingComposer,
      $$MessagesTableAnnotationComposer,
      $$MessagesTableCreateCompanionBuilder,
      $$MessagesTableUpdateCompanionBuilder,
      (Message, $$MessagesTableReferences),
      Message,
      PrefetchHooks Function({bool conversationId})
    >;

class $ChattDbManager {
  final _$ChattDb _db;
  $ChattDbManager(this._db);
  $$SettingsTableTableManager get settings =>
      $$SettingsTableTableManager(_db, _db.settings);
  $$PeersTableTableManager get peers =>
      $$PeersTableTableManager(_db, _db.peers);
  $$ConversationsTableTableManager get conversations =>
      $$ConversationsTableTableManager(_db, _db.conversations);
  $$MessagesTableTableManager get messages =>
      $$MessagesTableTableManager(_db, _db.messages);
}
