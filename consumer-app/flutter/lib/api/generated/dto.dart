// Generated from Pawday runtime OpenAPI; SHA256 9c5492015561a12b6a023da0c6c2e6dcaa3b63ca48169c99587cbbaaf98ccbbc
// ignore_for_file: non_constant_identifier_names, constant_identifier_names, use_null_aware_elements, prefer_null_aware_operators

class Meta {
  final String request_id;
  final String correlation_id;
  const Meta({required this.request_id, required this.correlation_id});
  factory Meta.fromJson(Map<String,dynamic> json) => Meta(
    request_id: json['request_id'] as String,
    correlation_id: json['correlation_id'] as String,
  );
  Map<String,dynamic> toJson() => {
    'request_id': request_id,
    'correlation_id': correlation_id,
  };
}

class Page {
  final String? next_cursor;
  final bool has_more;
  const Page({required this.next_cursor, required this.has_more});
  factory Page.fromJson(Map<String,dynamic> json) => Page(
    next_cursor: json['next_cursor'] == null ? null : json['next_cursor'] as String,
    has_more: json['has_more'] as bool,
  );
  Map<String,dynamic> toJson() => {
    'next_cursor': next_cursor == null ? null : next_cursor!,
    'has_more': has_more,
  };
}

class ErrorEnvelope {
  final Map<String,dynamic> error;
  final Meta meta;
  const ErrorEnvelope({required this.error, required this.meta});
  factory ErrorEnvelope.fromJson(Map<String,dynamic> json) => ErrorEnvelope(
    error: Map<String,dynamic>.from(json['error'] as Map),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'error': error,
    'meta': meta.toJson(),
  };
}

class Tokens {
  final String access_token;
  final String refresh_token;
  final int expires_in;
  final String session_id;
  final String? user_id;
  const Tokens({required this.access_token, required this.refresh_token, required this.expires_in, required this.session_id, required this.user_id});
  factory Tokens.fromJson(Map<String,dynamic> json) => Tokens(
    access_token: json['access_token'] as String,
    refresh_token: json['refresh_token'] as String,
    expires_in: (json['expires_in'] as num).toInt(),
    session_id: json['session_id'] as String,
    user_id: json['user_id'] == null ? null : json['user_id'] as String,
  );
  Map<String,dynamic> toJson() => {
    'access_token': access_token,
    'refresh_token': refresh_token,
    'expires_in': expires_in,
    'session_id': session_id,
    'user_id': user_id == null ? null : user_id!,
  };
}

class Receipt {
  final String id;
  final int version;
  final String accepted_at;
  const Receipt({required this.id, required this.version, required this.accepted_at});
  factory Receipt.fromJson(Map<String,dynamic> json) => Receipt(
    id: json['id'] as String,
    version: (json['version'] as num).toInt(),
    accepted_at: json['accepted_at'] as String,
  );
  Map<String,dynamic> toJson() => {
    'id': id,
    'version': version,
    'accepted_at': accepted_at,
  };
}

class Proof {
  final String reverify_token;
  final String action;
  final String expires_at;
  const Proof({required this.reverify_token, required this.action, required this.expires_at});
  factory Proof.fromJson(Map<String,dynamic> json) => Proof(
    reverify_token: json['reverify_token'] as String,
    action: json['action'] as String,
    expires_at: json['expires_at'] as String,
  );
  Map<String,dynamic> toJson() => {
    'reverify_token': reverify_token,
    'action': action,
    'expires_at': expires_at,
  };
}

class Principal {
  final String id;
  final String realm;
  final String? user_id;
  final String? merchant_id;
  final String session_id;
  final List<String> permissions;
  const Principal({required this.id, required this.realm, required this.user_id, required this.merchant_id, required this.session_id, required this.permissions});
  factory Principal.fromJson(Map<String,dynamic> json) => Principal(
    id: json['id'] as String,
    realm: json['realm'] as String,
    user_id: json['user_id'] == null ? null : json['user_id'] as String,
    merchant_id: json['merchant_id'] == null ? null : json['merchant_id'] as String,
    session_id: json['session_id'] as String,
    permissions: (json['permissions'] as List).map((value) => value as String).toList(),
  );
  Map<String,dynamic> toJson() => {
    'id': id,
    'realm': realm,
    'user_id': user_id == null ? null : user_id!,
    'merchant_id': merchant_id == null ? null : merchant_id!,
    'session_id': session_id,
    'permissions': permissions.map((value) => value).toList(),
  };
}

class Session {
  final String id;
  final String device_id;
  final String created_at;
  final String expires_at;
  final String? revoked_at;
  const Session({required this.id, required this.device_id, required this.created_at, required this.expires_at, required this.revoked_at});
  factory Session.fromJson(Map<String,dynamic> json) => Session(
    id: json['id'] as String,
    device_id: json['device_id'] as String,
    created_at: json['created_at'] as String,
    expires_at: json['expires_at'] as String,
    revoked_at: json['revoked_at'] == null ? null : json['revoked_at'] as String,
  );
  Map<String,dynamic> toJson() => {
    'id': id,
    'device_id': device_id,
    'created_at': created_at,
    'expires_at': expires_at,
    'revoked_at': revoked_at == null ? null : revoked_at!,
  };
}

class Store {
  final String id;
  final String merchant_id;
  final String name;
  const Store({required this.id, required this.merchant_id, required this.name});
  factory Store.fromJson(Map<String,dynamic> json) => Store(
    id: json['id'] as String,
    merchant_id: json['merchant_id'] as String,
    name: json['name'] as String,
  );
  Map<String,dynamic> toJson() => {
    'id': id,
    'merchant_id': merchant_id,
    'name': name,
  };
}

class Role {
  final String id;
  final String name;
  final List<String> permission_codes;
  final int version;
  const Role({required this.id, required this.name, required this.permission_codes, required this.version});
  factory Role.fromJson(Map<String,dynamic> json) => Role(
    id: json['id'] as String,
    name: json['name'] as String,
    permission_codes: (json['permission_codes'] as List).map((value) => value as String).toList(),
    version: (json['version'] as num).toInt(),
  );
  Map<String,dynamic> toJson() => {
    'id': id,
    'name': name,
    'permission_codes': permission_codes.map((value) => value).toList(),
    'version': version,
  };
}

class Audit {
  final String id;
  final String actor_type;
  final String? actor_id;
  final String action;
  final String object_type;
  final String? object_id;
  final Map<String,dynamic>? before_json;
  final Map<String,dynamic>? after_json;
  final String? request_id;
  final String? correlation_id;
  final String created_at;
  const Audit({required this.id, required this.actor_type, required this.actor_id, required this.action, required this.object_type, required this.object_id, required this.before_json, required this.after_json, required this.request_id, required this.correlation_id, required this.created_at});
  factory Audit.fromJson(Map<String,dynamic> json) => Audit(
    id: json['id'] as String,
    actor_type: json['actor_type'] as String,
    actor_id: json['actor_id'] == null ? null : json['actor_id'] as String,
    action: json['action'] as String,
    object_type: json['object_type'] as String,
    object_id: json['object_id'] == null ? null : json['object_id'] as String,
    before_json: json['before_json'] == null ? null : Map<String,dynamic>.from(json['before_json'] as Map),
    after_json: json['after_json'] == null ? null : Map<String,dynamic>.from(json['after_json'] as Map),
    request_id: json['request_id'] == null ? null : json['request_id'] as String,
    correlation_id: json['correlation_id'] == null ? null : json['correlation_id'] as String,
    created_at: json['created_at'] as String,
  );
  Map<String,dynamic> toJson() => {
    'id': id,
    'actor_type': actor_type,
    'actor_id': actor_id == null ? null : actor_id!,
    'action': action,
    'object_type': object_type,
    'object_id': object_id == null ? null : object_id!,
    'before_json': before_json == null ? null : before_json!,
    'after_json': after_json == null ? null : after_json!,
    'request_id': request_id == null ? null : request_id!,
    'correlation_id': correlation_id == null ? null : correlation_id!,
    'created_at': created_at,
  };
}

class CodeRequest {
  final String phone_e164;
  final String purpose;
  const CodeRequest({required this.phone_e164, required this.purpose});
  factory CodeRequest.fromJson(Map<String,dynamic> json) => CodeRequest(
    phone_e164: json['phone_e164'] as String,
    purpose: json['purpose'] as String,
  );
  Map<String,dynamic> toJson() => {
    'phone_e164': phone_e164,
    'purpose': purpose,
  };
}

class PhoneLogin {
  final String phone_e164;
  final String code;
  final String device_id;
  const PhoneLogin({required this.phone_e164, required this.code, required this.device_id});
  factory PhoneLogin.fromJson(Map<String,dynamic> json) => PhoneLogin(
    phone_e164: json['phone_e164'] as String,
    code: json['code'] as String,
    device_id: json['device_id'] as String,
  );
  Map<String,dynamic> toJson() => {
    'phone_e164': phone_e164,
    'code': code,
    'device_id': device_id,
  };
}

class StaffLogin {
  final String login_name;
  final String password;
  final String? totp_code;
  final String device_id;
  const StaffLogin({required this.login_name, required this.password, this.totp_code, required this.device_id});
  factory StaffLogin.fromJson(Map<String,dynamic> json) => StaffLogin(
    login_name: json['login_name'] as String,
    password: json['password'] as String,
    totp_code: json['totp_code'] == null ? null : json['totp_code'] as String,
    device_id: json['device_id'] as String,
  );
  Map<String,dynamic> toJson() => {
    'login_name': login_name,
    'password': password,
    if (totp_code != null) 'totp_code': totp_code == null ? null : totp_code!,
    'device_id': device_id,
  };
}

class AdminLogin {
  final String login_name;
  final String password;
  final String totp_code;
  final String device_id;
  const AdminLogin({required this.login_name, required this.password, required this.totp_code, required this.device_id});
  factory AdminLogin.fromJson(Map<String,dynamic> json) => AdminLogin(
    login_name: json['login_name'] as String,
    password: json['password'] as String,
    totp_code: json['totp_code'] as String,
    device_id: json['device_id'] as String,
  );
  Map<String,dynamic> toJson() => {
    'login_name': login_name,
    'password': password,
    'totp_code': totp_code,
    'device_id': device_id,
  };
}

class Refresh {
  final String refresh_token;
  const Refresh({required this.refresh_token});
  factory Refresh.fromJson(Map<String,dynamic> json) => Refresh(
    refresh_token: json['refresh_token'] as String,
  );
  Map<String,dynamic> toJson() => {
    'refresh_token': refresh_token,
  };
}

class Reverify {
  final String action;
  final String? password;
  final String? otp_code;
  final String? totp_code;
  const Reverify({required this.action, this.password, this.otp_code, this.totp_code});
  factory Reverify.fromJson(Map<String,dynamic> json) => Reverify(
    action: json['action'] as String,
    password: json['password'] == null ? null : json['password'] as String,
    otp_code: json['otp_code'] == null ? null : json['otp_code'] as String,
    totp_code: json['totp_code'] == null ? null : json['totp_code'] as String,
  );
  Map<String,dynamic> toJson() => {
    'action': action,
    if (password != null) 'password': password == null ? null : password!,
    if (otp_code != null) 'otp_code': otp_code == null ? null : otp_code!,
    if (totp_code != null) 'totp_code': totp_code == null ? null : totp_code!,
  };
}

class RoleRequest {
  final String name;
  final List<String> permission_codes;
  const RoleRequest({required this.name, required this.permission_codes});
  factory RoleRequest.fromJson(Map<String,dynamic> json) => RoleRequest(
    name: json['name'] as String,
    permission_codes: (json['permission_codes'] as List).map((value) => value as String).toList(),
  );
  Map<String,dynamic> toJson() => {
    'name': name,
    'permission_codes': permission_codes.map((value) => value).toList(),
  };
}

class TokensEnvelope {
  final Tokens data;
  final Meta meta;
  const TokensEnvelope({required this.data, required this.meta});
  factory TokensEnvelope.fromJson(Map<String,dynamic> json) => TokensEnvelope(
    data: Tokens.fromJson(Map<String,dynamic>.from(json['data'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.toJson(),
    'meta': meta.toJson(),
  };
}

class ReceiptEnvelope {
  final Receipt data;
  final Meta meta;
  const ReceiptEnvelope({required this.data, required this.meta});
  factory ReceiptEnvelope.fromJson(Map<String,dynamic> json) => ReceiptEnvelope(
    data: Receipt.fromJson(Map<String,dynamic>.from(json['data'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.toJson(),
    'meta': meta.toJson(),
  };
}

class ProofEnvelope {
  final Proof data;
  final Meta meta;
  const ProofEnvelope({required this.data, required this.meta});
  factory ProofEnvelope.fromJson(Map<String,dynamic> json) => ProofEnvelope(
    data: Proof.fromJson(Map<String,dynamic>.from(json['data'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.toJson(),
    'meta': meta.toJson(),
  };
}

class PrincipalEnvelope {
  final Principal data;
  final Meta meta;
  const PrincipalEnvelope({required this.data, required this.meta});
  factory PrincipalEnvelope.fromJson(Map<String,dynamic> json) => PrincipalEnvelope(
    data: Principal.fromJson(Map<String,dynamic>.from(json['data'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.toJson(),
    'meta': meta.toJson(),
  };
}

class StoreEnvelope {
  final Store data;
  final Meta meta;
  const StoreEnvelope({required this.data, required this.meta});
  factory StoreEnvelope.fromJson(Map<String,dynamic> json) => StoreEnvelope(
    data: Store.fromJson(Map<String,dynamic>.from(json['data'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.toJson(),
    'meta': meta.toJson(),
  };
}

class RoleEnvelope {
  final Role data;
  final Meta meta;
  const RoleEnvelope({required this.data, required this.meta});
  factory RoleEnvelope.fromJson(Map<String,dynamic> json) => RoleEnvelope(
    data: Role.fromJson(Map<String,dynamic>.from(json['data'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.toJson(),
    'meta': meta.toJson(),
  };
}

class SessionList {
  final List<Session> data;
  final Page page;
  final Meta meta;
  const SessionList({required this.data, required this.page, required this.meta});
  factory SessionList.fromJson(Map<String,dynamic> json) => SessionList(
    data: (json['data'] as List).map((value) => Session.fromJson(Map<String,dynamic>.from(value as Map))).toList(),
    page: Page.fromJson(Map<String,dynamic>.from(json['page'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.map((value) => value.toJson()).toList(),
    'page': page.toJson(),
    'meta': meta.toJson(),
  };
}

class StoreList {
  final List<Store> data;
  final Page page;
  final Meta meta;
  const StoreList({required this.data, required this.page, required this.meta});
  factory StoreList.fromJson(Map<String,dynamic> json) => StoreList(
    data: (json['data'] as List).map((value) => Store.fromJson(Map<String,dynamic>.from(value as Map))).toList(),
    page: Page.fromJson(Map<String,dynamic>.from(json['page'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.map((value) => value.toJson()).toList(),
    'page': page.toJson(),
    'meta': meta.toJson(),
  };
}

class RoleList {
  final List<Role> data;
  final Page page;
  final Meta meta;
  const RoleList({required this.data, required this.page, required this.meta});
  factory RoleList.fromJson(Map<String,dynamic> json) => RoleList(
    data: (json['data'] as List).map((value) => Role.fromJson(Map<String,dynamic>.from(value as Map))).toList(),
    page: Page.fromJson(Map<String,dynamic>.from(json['page'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.map((value) => value.toJson()).toList(),
    'page': page.toJson(),
    'meta': meta.toJson(),
  };
}

class AuditList {
  final List<Audit> data;
  final Page page;
  final Meta meta;
  const AuditList({required this.data, required this.page, required this.meta});
  factory AuditList.fromJson(Map<String,dynamic> json) => AuditList(
    data: (json['data'] as List).map((value) => Audit.fromJson(Map<String,dynamic>.from(value as Map))).toList(),
    page: Page.fromJson(Map<String,dynamic>.from(json['page'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.map((value) => value.toJson()).toList(),
    'page': page.toJson(),
    'meta': meta.toJson(),
  };
}

class OutboxRow {
  final String id;
  final String root_event_id;
  final String event_type;
  final int event_version;
  final String transport_kind;
  final String status;
  final int attempt_count;
  final String available_at;
  final String? lease_expires_at;
  final String? last_error_code;
  final String? dead_at;
  final int generation;
  final String created_at;
  const OutboxRow({required this.id, required this.root_event_id, required this.event_type, required this.event_version, required this.transport_kind, required this.status, required this.attempt_count, required this.available_at, required this.lease_expires_at, required this.last_error_code, required this.dead_at, required this.generation, required this.created_at});
  factory OutboxRow.fromJson(Map<String,dynamic> json) => OutboxRow(
    id: json['id'] as String,
    root_event_id: json['root_event_id'] as String,
    event_type: json['event_type'] as String,
    event_version: (json['event_version'] as num).toInt(),
    transport_kind: json['transport_kind'] as String,
    status: json['status'] as String,
    attempt_count: (json['attempt_count'] as num).toInt(),
    available_at: json['available_at'] as String,
    lease_expires_at: json['lease_expires_at'] == null ? null : json['lease_expires_at'] as String,
    last_error_code: json['last_error_code'] == null ? null : json['last_error_code'] as String,
    dead_at: json['dead_at'] == null ? null : json['dead_at'] as String,
    generation: (json['generation'] as num).toInt(),
    created_at: json['created_at'] as String,
  );
  Map<String,dynamic> toJson() => {
    'id': id,
    'root_event_id': root_event_id,
    'event_type': event_type,
    'event_version': event_version,
    'transport_kind': transport_kind,
    'status': status,
    'attempt_count': attempt_count,
    'available_at': available_at,
    'lease_expires_at': lease_expires_at == null ? null : lease_expires_at!,
    'last_error_code': last_error_code == null ? null : last_error_code!,
    'dead_at': dead_at == null ? null : dead_at!,
    'generation': generation,
    'created_at': created_at,
  };
}

class OutboxList {
  final List<OutboxRow> data;
  final Page page;
  final Meta meta;
  const OutboxList({required this.data, required this.page, required this.meta});
  factory OutboxList.fromJson(Map<String,dynamic> json) => OutboxList(
    data: (json['data'] as List).map((value) => OutboxRow.fromJson(Map<String,dynamic>.from(value as Map))).toList(),
    page: Page.fromJson(Map<String,dynamic>.from(json['page'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.map((value) => value.toJson()).toList(),
    'page': page.toJson(),
    'meta': meta.toJson(),
  };
}

class OutboxStats {
  final List<Map<String,dynamic>> status_counts;
  final int backlog;
  final double oldest_event_age_seconds;
  final int inbox_dead;
  final int sms_dead;
  const OutboxStats({required this.status_counts, required this.backlog, required this.oldest_event_age_seconds, required this.inbox_dead, required this.sms_dead});
  factory OutboxStats.fromJson(Map<String,dynamic> json) => OutboxStats(
    status_counts: (json['status_counts'] as List).map((value) => Map<String,dynamic>.from(value as Map)).toList(),
    backlog: (json['backlog'] as num).toInt(),
    oldest_event_age_seconds: (json['oldest_event_age_seconds'] as num).toDouble(),
    inbox_dead: (json['inbox_dead'] as num).toInt(),
    sms_dead: (json['sms_dead'] as num).toInt(),
  );
  Map<String,dynamic> toJson() => {
    'status_counts': status_counts.map((value) => value).toList(),
    'backlog': backlog,
    'oldest_event_age_seconds': oldest_event_age_seconds,
    'inbox_dead': inbox_dead,
    'sms_dead': sms_dead,
  };
}

class OutboxStatsEnvelope {
  final OutboxStats data;
  final Meta meta;
  const OutboxStatsEnvelope({required this.data, required this.meta});
  factory OutboxStatsEnvelope.fromJson(Map<String,dynamic> json) => OutboxStatsEnvelope(
    data: OutboxStats.fromJson(Map<String,dynamic>.from(json['data'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.toJson(),
    'meta': meta.toJson(),
  };
}

class ReplayRequest {
  final int expected_generation;
  final String reason_code;
  const ReplayRequest({required this.expected_generation, required this.reason_code});
  factory ReplayRequest.fromJson(Map<String,dynamic> json) => ReplayRequest(
    expected_generation: (json['expected_generation'] as num).toInt(),
    reason_code: json['reason_code'] as String,
  );
  Map<String,dynamic> toJson() => {
    'expected_generation': expected_generation,
    'reason_code': reason_code,
  };
}

class ReplayReceipt {
  final String event_id;
  final int generation;
  final String status;
  const ReplayReceipt({required this.event_id, required this.generation, required this.status});
  factory ReplayReceipt.fromJson(Map<String,dynamic> json) => ReplayReceipt(
    event_id: json['event_id'] as String,
    generation: (json['generation'] as num).toInt(),
    status: json['status'] as String,
  );
  Map<String,dynamic> toJson() => {
    'event_id': event_id,
    'generation': generation,
    'status': status,
  };
}

class ReplayReceiptEnvelope {
  final ReplayReceipt data;
  final Meta meta;
  const ReplayReceiptEnvelope({required this.data, required this.meta});
  factory ReplayReceiptEnvelope.fromJson(Map<String,dynamic> json) => ReplayReceiptEnvelope(
    data: ReplayReceipt.fromJson(Map<String,dynamic>.from(json['data'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.toJson(),
    'meta': meta.toJson(),
  };
}

class MediaGrantRequest {
  final String scope;
  final String mime;
  final int size_bytes;
  final String sha256;
  final String? store_id;
  const MediaGrantRequest({required this.scope, required this.mime, required this.size_bytes, required this.sha256, this.store_id});
  factory MediaGrantRequest.fromJson(Map<String,dynamic> json) => MediaGrantRequest(
    scope: json['scope'] as String,
    mime: json['mime'] as String,
    size_bytes: (json['size_bytes'] as num).toInt(),
    sha256: json['sha256'] as String,
    store_id: json['store_id'] == null ? null : json['store_id'] as String,
  );
  Map<String,dynamic> toJson() => {
    'scope': scope,
    'mime': mime,
    'size_bytes': size_bytes,
    'sha256': sha256,
    if (store_id != null) 'store_id': store_id == null ? null : store_id!,
  };
}

class MediaGrant {
  final String asset_id;
  final String upload_token;
  final String upload_url;
  final String expires_at;
  final String status;
  const MediaGrant({required this.asset_id, required this.upload_token, required this.upload_url, required this.expires_at, required this.status});
  factory MediaGrant.fromJson(Map<String,dynamic> json) => MediaGrant(
    asset_id: json['asset_id'] as String,
    upload_token: json['upload_token'] as String,
    upload_url: json['upload_url'] as String,
    expires_at: json['expires_at'] as String,
    status: json['status'] as String,
  );
  Map<String,dynamic> toJson() => {
    'asset_id': asset_id,
    'upload_token': upload_token,
    'upload_url': upload_url,
    'expires_at': expires_at,
    'status': status,
  };
}

class MediaAsset {
  final String asset_id;
  final String owner_id;
  final String realm;
  final String scope;
  final String? store_id;
  final String storage_provider;
  final String object_key;
  final String mime;
  final int size_bytes;
  final String sha256;
  final String status;
  final String? error_code;
  final String created_at;
  final String updated_at;
  const MediaAsset({required this.asset_id, required this.owner_id, required this.realm, required this.scope, required this.store_id, required this.storage_provider, required this.object_key, required this.mime, required this.size_bytes, required this.sha256, required this.status, required this.error_code, required this.created_at, required this.updated_at});
  factory MediaAsset.fromJson(Map<String,dynamic> json) => MediaAsset(
    asset_id: json['asset_id'] as String,
    owner_id: json['owner_id'] as String,
    realm: json['realm'] as String,
    scope: json['scope'] as String,
    store_id: json['store_id'] == null ? null : json['store_id'] as String,
    storage_provider: json['storage_provider'] as String,
    object_key: json['object_key'] as String,
    mime: json['mime'] as String,
    size_bytes: (json['size_bytes'] as num).toInt(),
    sha256: json['sha256'] as String,
    status: json['status'] as String,
    error_code: json['error_code'] == null ? null : json['error_code'] as String,
    created_at: json['created_at'] as String,
    updated_at: json['updated_at'] as String,
  );
  Map<String,dynamic> toJson() => {
    'asset_id': asset_id,
    'owner_id': owner_id,
    'realm': realm,
    'scope': scope,
    'store_id': store_id == null ? null : store_id!,
    'storage_provider': storage_provider,
    'object_key': object_key,
    'mime': mime,
    'size_bytes': size_bytes,
    'sha256': sha256,
    'status': status,
    'error_code': error_code == null ? null : error_code!,
    'created_at': created_at,
    'updated_at': updated_at,
  };
}

class SearchVersion {
  final String index_name;
  final int schema_version;
  final String status;
  final String created_at;
  final String? activated_at;
  const SearchVersion({required this.index_name, required this.schema_version, required this.status, required this.created_at, required this.activated_at});
  factory SearchVersion.fromJson(Map<String,dynamic> json) => SearchVersion(
    index_name: json['index_name'] as String,
    schema_version: (json['schema_version'] as num).toInt(),
    status: json['status'] as String,
    created_at: json['created_at'] as String,
    activated_at: json['activated_at'] == null ? null : json['activated_at'] as String,
  );
  Map<String,dynamic> toJson() => {
    'index_name': index_name,
    'schema_version': schema_version,
    'status': status,
    'created_at': created_at,
    'activated_at': activated_at == null ? null : activated_at!,
  };
}

class SearchRebuildJob {
  final String id;
  final String? event_id;
  final String target_index;
  final String status;
  final int attempt_count;
  final String? last_error_code;
  final int? validated_count;
  final String? source_digest;
  final String? completed_at;
  final String created_at;
  const SearchRebuildJob({required this.id, required this.event_id, required this.target_index, required this.status, required this.attempt_count, required this.last_error_code, required this.validated_count, required this.source_digest, required this.completed_at, required this.created_at});
  factory SearchRebuildJob.fromJson(Map<String,dynamic> json) => SearchRebuildJob(
    id: json['id'] as String,
    event_id: json['event_id'] == null ? null : json['event_id'] as String,
    target_index: json['target_index'] as String,
    status: json['status'] as String,
    attempt_count: (json['attempt_count'] as num).toInt(),
    last_error_code: json['last_error_code'] == null ? null : json['last_error_code'] as String,
    validated_count: json['validated_count'] == null ? null : (json['validated_count'] as num).toInt(),
    source_digest: json['source_digest'] == null ? null : json['source_digest'] as String,
    completed_at: json['completed_at'] == null ? null : json['completed_at'] as String,
    created_at: json['created_at'] as String,
  );
  Map<String,dynamic> toJson() => {
    'id': id,
    'event_id': event_id == null ? null : event_id!,
    'target_index': target_index,
    'status': status,
    'attempt_count': attempt_count,
    'last_error_code': last_error_code == null ? null : last_error_code!,
    'validated_count': validated_count == null ? null : validated_count!,
    'source_digest': source_digest == null ? null : source_digest!,
    'completed_at': completed_at == null ? null : completed_at!,
    'created_at': created_at,
  };
}

class SearchStatus {
  final int schema_version;
  final String? active_index;
  final List<SearchVersion> versions;
  final List<Map<String,dynamic>> task_counts;
  final List<SearchRebuildJob> rebuild_jobs;
  const SearchStatus({required this.schema_version, required this.active_index, required this.versions, required this.task_counts, required this.rebuild_jobs});
  factory SearchStatus.fromJson(Map<String,dynamic> json) => SearchStatus(
    schema_version: (json['schema_version'] as num).toInt(),
    active_index: json['active_index'] == null ? null : json['active_index'] as String,
    versions: (json['versions'] as List).map((value) => SearchVersion.fromJson(Map<String,dynamic>.from(value as Map))).toList(),
    task_counts: (json['task_counts'] as List).map((value) => Map<String,dynamic>.from(value as Map)).toList(),
    rebuild_jobs: (json['rebuild_jobs'] as List).map((value) => SearchRebuildJob.fromJson(Map<String,dynamic>.from(value as Map))).toList(),
  );
  Map<String,dynamic> toJson() => {
    'schema_version': schema_version,
    'active_index': active_index == null ? null : active_index!,
    'versions': versions.map((value) => value.toJson()).toList(),
    'task_counts': task_counts.map((value) => value).toList(),
    'rebuild_jobs': rebuild_jobs.map((value) => value.toJson()).toList(),
  };
}

class SearchCommandRequest {
  final String reason_code;
  const SearchCommandRequest({required this.reason_code});
  factory SearchCommandRequest.fromJson(Map<String,dynamic> json) => SearchCommandRequest(
    reason_code: json['reason_code'] as String,
  );
  Map<String,dynamic> toJson() => {
    'reason_code': reason_code,
  };
}

class SearchCommandReceipt {
  final String request_id;
  final String kind;
  final String status;
  final int affected_count;
  const SearchCommandReceipt({required this.request_id, required this.kind, required this.status, required this.affected_count});
  factory SearchCommandReceipt.fromJson(Map<String,dynamic> json) => SearchCommandReceipt(
    request_id: json['request_id'] as String,
    kind: json['kind'] as String,
    status: json['status'] as String,
    affected_count: (json['affected_count'] as num).toInt(),
  );
  Map<String,dynamic> toJson() => {
    'request_id': request_id,
    'kind': kind,
    'status': status,
    'affected_count': affected_count,
  };
}

class MediaGrantEnvelope {
  final MediaGrant data;
  final Meta meta;
  const MediaGrantEnvelope({required this.data, required this.meta});
  factory MediaGrantEnvelope.fromJson(Map<String,dynamic> json) => MediaGrantEnvelope(
    data: MediaGrant.fromJson(Map<String,dynamic>.from(json['data'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.toJson(),
    'meta': meta.toJson(),
  };
}

class MediaAssetEnvelope {
  final MediaAsset data;
  final Meta meta;
  const MediaAssetEnvelope({required this.data, required this.meta});
  factory MediaAssetEnvelope.fromJson(Map<String,dynamic> json) => MediaAssetEnvelope(
    data: MediaAsset.fromJson(Map<String,dynamic>.from(json['data'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.toJson(),
    'meta': meta.toJson(),
  };
}

class SearchStatusEnvelope {
  final SearchStatus data;
  final Meta meta;
  const SearchStatusEnvelope({required this.data, required this.meta});
  factory SearchStatusEnvelope.fromJson(Map<String,dynamic> json) => SearchStatusEnvelope(
    data: SearchStatus.fromJson(Map<String,dynamic>.from(json['data'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.toJson(),
    'meta': meta.toJson(),
  };
}

class SearchCommandReceiptEnvelope {
  final SearchCommandReceipt data;
  final Meta meta;
  const SearchCommandReceiptEnvelope({required this.data, required this.meta});
  factory SearchCommandReceiptEnvelope.fromJson(Map<String,dynamic> json) => SearchCommandReceiptEnvelope(
    data: SearchCommandReceipt.fromJson(Map<String,dynamic>.from(json['data'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.toJson(),
    'meta': meta.toJson(),
  };
}

class LifeStage {
  final String id;
  final String species_id;
  final String stage_code;
  final String display_name;
  final String rule_version_id;
  final int? min_age_value;
  final int? max_age_value;
  final String age_unit;
  final bool is_unknown;
  const LifeStage({required this.id, required this.species_id, required this.stage_code, required this.display_name, required this.rule_version_id, required this.min_age_value, required this.max_age_value, required this.age_unit, required this.is_unknown});
  factory LifeStage.fromJson(Map<String,dynamic> json) => LifeStage(
    id: json['id'] as String,
    species_id: json['species_id'] as String,
    stage_code: json['stage_code'] as String,
    display_name: json['display_name'] as String,
    rule_version_id: json['rule_version_id'] as String,
    min_age_value: json['min_age_value'] == null ? null : (json['min_age_value'] as num).toInt(),
    max_age_value: json['max_age_value'] == null ? null : (json['max_age_value'] as num).toInt(),
    age_unit: json['age_unit'] as String,
    is_unknown: json['is_unknown'] as bool,
  );
  Map<String,dynamic> toJson() => {
    'id': id,
    'species_id': species_id,
    'stage_code': stage_code,
    'display_name': display_name,
    'rule_version_id': rule_version_id,
    'min_age_value': min_age_value == null ? null : min_age_value!,
    'max_age_value': max_age_value == null ? null : max_age_value!,
    'age_unit': age_unit,
    'is_unknown': is_unknown,
  };
}

class Species {
  final String id;
  final String? parent_id;
  final String name;
  final String category;
  final List<LifeStage> life_stages;
  const Species({required this.id, required this.parent_id, required this.name, required this.category, required this.life_stages});
  factory Species.fromJson(Map<String,dynamic> json) => Species(
    id: json['id'] as String,
    parent_id: json['parent_id'] == null ? null : json['parent_id'] as String,
    name: json['name'] as String,
    category: json['category'] as String,
    life_stages: (json['life_stages'] as List).map((value) => LifeStage.fromJson(Map<String,dynamic>.from(value as Map))).toList(),
  );
  Map<String,dynamic> toJson() => {
    'id': id,
    'parent_id': parent_id == null ? null : parent_id!,
    'name': name,
    'category': category,
    'life_stages': life_stages.map((value) => value.toJson()).toList(),
  };
}

class AllergenEntry {
  final String allergen_id;
  final String status;
  final String source;
  final String? note;
  const AllergenEntry({required this.allergen_id, required this.status, required this.source, this.note});
  factory AllergenEntry.fromJson(Map<String,dynamic> json) => AllergenEntry(
    allergen_id: json['allergen_id'] as String,
    status: json['status'] as String,
    source: json['source'] as String,
    note: json['note'] == null ? null : json['note'] as String,
  );
  Map<String,dynamic> toJson() => {
    'allergen_id': allergen_id,
    'status': status,
    'source': source,
    if (note != null) 'note': note == null ? null : note!,
  };
}

class PetRequest {
  final String name;
  final String species_id;
  final String? breed_id;
  final String? birth_date;
  final int? age_estimate_months;
  final String sex;
  final String neutered_status;
  final List<AllergenEntry> allergens;
  final List<String> avoidance_notes;
  const PetRequest({required this.name, required this.species_id, this.breed_id, this.birth_date, this.age_estimate_months, required this.sex, required this.neutered_status, required this.allergens, required this.avoidance_notes});
  factory PetRequest.fromJson(Map<String,dynamic> json) => PetRequest(
    name: json['name'] as String,
    species_id: json['species_id'] as String,
    breed_id: json['breed_id'] == null ? null : json['breed_id'] as String,
    birth_date: json['birth_date'] == null ? null : json['birth_date'] as String,
    age_estimate_months: json['age_estimate_months'] == null ? null : (json['age_estimate_months'] as num).toInt(),
    sex: json['sex'] as String,
    neutered_status: json['neutered_status'] as String,
    allergens: (json['allergens'] as List).map((value) => AllergenEntry.fromJson(Map<String,dynamic>.from(value as Map))).toList(),
    avoidance_notes: (json['avoidance_notes'] as List).map((value) => value as String).toList(),
  );
  Map<String,dynamic> toJson() => {
    'name': name,
    'species_id': species_id,
    if (breed_id != null) 'breed_id': breed_id == null ? null : breed_id!,
    if (birth_date != null) 'birth_date': birth_date == null ? null : birth_date!,
    if (age_estimate_months != null) 'age_estimate_months': age_estimate_months == null ? null : age_estimate_months!,
    'sex': sex,
    'neutered_status': neutered_status,
    'allergens': allergens.map((value) => value.toJson()).toList(),
    'avoidance_notes': avoidance_notes.map((value) => value).toList(),
  };
}

class PetPatch {
  final String? name;
  final String? species_id;
  final String? breed_id;
  final String? birth_date;
  final int? age_estimate_months;
  final String? sex;
  final String? neutered_status;
  final List<AllergenEntry>? allergens;
  final List<String>? avoidance_notes;
  const PetPatch({this.name, this.species_id, this.breed_id, this.birth_date, this.age_estimate_months, this.sex, this.neutered_status, this.allergens, this.avoidance_notes});
  factory PetPatch.fromJson(Map<String,dynamic> json) => PetPatch(
    name: json['name'] == null ? null : json['name'] as String,
    species_id: json['species_id'] == null ? null : json['species_id'] as String,
    breed_id: json['breed_id'] == null ? null : json['breed_id'] as String,
    birth_date: json['birth_date'] == null ? null : json['birth_date'] as String,
    age_estimate_months: json['age_estimate_months'] == null ? null : (json['age_estimate_months'] as num).toInt(),
    sex: json['sex'] == null ? null : json['sex'] as String,
    neutered_status: json['neutered_status'] == null ? null : json['neutered_status'] as String,
    allergens: json['allergens'] == null ? null : (json['allergens'] as List).map((value) => AllergenEntry.fromJson(Map<String,dynamic>.from(value as Map))).toList(),
    avoidance_notes: json['avoidance_notes'] == null ? null : (json['avoidance_notes'] as List).map((value) => value as String).toList(),
  );
  Map<String,dynamic> toJson() => {
    if (name != null) 'name': name == null ? null : name!,
    if (species_id != null) 'species_id': species_id == null ? null : species_id!,
    if (breed_id != null) 'breed_id': breed_id == null ? null : breed_id!,
    if (birth_date != null) 'birth_date': birth_date == null ? null : birth_date!,
    if (age_estimate_months != null) 'age_estimate_months': age_estimate_months == null ? null : age_estimate_months!,
    if (sex != null) 'sex': sex == null ? null : sex!,
    if (neutered_status != null) 'neutered_status': neutered_status == null ? null : neutered_status!,
    if (allergens != null) 'allergens': allergens == null ? null : allergens!.map((value) => value.toJson()).toList(),
    if (avoidance_notes != null) 'avoidance_notes': avoidance_notes == null ? null : avoidance_notes!.map((value) => value).toList(),
  };
}

class Pet {
  final String name;
  final String species_id;
  final String? breed_id;
  final String? birth_date;
  final int? age_estimate_months;
  final String sex;
  final String neutered_status;
  final List<AllergenEntry>? allergens;
  final List<String>? avoidance_notes;
  final String id;
  final int version;
  final String? life_stage_id;
  final bool life_stage_unknown;
  const Pet({required this.name, required this.species_id, this.breed_id, this.birth_date, this.age_estimate_months, required this.sex, required this.neutered_status, this.allergens, this.avoidance_notes, required this.id, required this.version, this.life_stage_id, required this.life_stage_unknown});
  factory Pet.fromJson(Map<String,dynamic> json) => Pet(
    name: json['name'] as String,
    species_id: json['species_id'] as String,
    breed_id: json['breed_id'] == null ? null : json['breed_id'] as String,
    birth_date: json['birth_date'] == null ? null : json['birth_date'] as String,
    age_estimate_months: json['age_estimate_months'] == null ? null : (json['age_estimate_months'] as num).toInt(),
    sex: json['sex'] as String,
    neutered_status: json['neutered_status'] as String,
    allergens: json['allergens'] == null ? null : (json['allergens'] as List).map((value) => AllergenEntry.fromJson(Map<String,dynamic>.from(value as Map))).toList(),
    avoidance_notes: json['avoidance_notes'] == null ? null : (json['avoidance_notes'] as List).map((value) => value as String).toList(),
    id: json['id'] as String,
    version: (json['version'] as num).toInt(),
    life_stage_id: json['life_stage_id'] == null ? null : json['life_stage_id'] as String,
    life_stage_unknown: json['life_stage_unknown'] as bool,
  );
  Map<String,dynamic> toJson() => {
    'name': name,
    'species_id': species_id,
    if (breed_id != null) 'breed_id': breed_id == null ? null : breed_id!,
    if (birth_date != null) 'birth_date': birth_date == null ? null : birth_date!,
    if (age_estimate_months != null) 'age_estimate_months': age_estimate_months == null ? null : age_estimate_months!,
    'sex': sex,
    'neutered_status': neutered_status,
    if (allergens != null) 'allergens': allergens == null ? null : allergens!.map((value) => value.toJson()).toList(),
    if (avoidance_notes != null) 'avoidance_notes': avoidance_notes == null ? null : avoidance_notes!.map((value) => value).toList(),
    'id': id,
    'version': version,
    if (life_stage_id != null) 'life_stage_id': life_stage_id == null ? null : life_stage_id!,
    'life_stage_unknown': life_stage_unknown,
  };
}

class Breed {
  final String id;
  final String species_id;
  final String name;
  const Breed({required this.id, required this.species_id, required this.name});
  factory Breed.fromJson(Map<String,dynamic> json) => Breed(
    id: json['id'] as String,
    species_id: json['species_id'] as String,
    name: json['name'] as String,
  );
  Map<String,dynamic> toJson() => {
    'id': id,
    'species_id': species_id,
    'name': name,
  };
}

class Allergen {
  final String id;
  final String name;
  const Allergen({required this.id, required this.name});
  factory Allergen.fromJson(Map<String,dynamic> json) => Allergen(
    id: json['id'] as String,
    name: json['name'] as String,
  );
  Map<String,dynamic> toJson() => {
    'id': id,
    'name': name,
  };
}

class Weight {
  final String id;
  final int weight_g;
  final String recorded_on;
  final String source;
  const Weight({required this.id, required this.weight_g, required this.recorded_on, required this.source});
  factory Weight.fromJson(Map<String,dynamic> json) => Weight(
    id: json['id'] as String,
    weight_g: (json['weight_g'] as num).toInt(),
    recorded_on: json['recorded_on'] as String,
    source: json['source'] as String,
  );
  Map<String,dynamic> toJson() => {
    'id': id,
    'weight_g': weight_g,
    'recorded_on': recorded_on,
    'source': source,
  };
}

class WeightRequest {
  final int weight_g;
  final String recorded_on;
  final String source;
  const WeightRequest({required this.weight_g, required this.recorded_on, required this.source});
  factory WeightRequest.fromJson(Map<String,dynamic> json) => WeightRequest(
    weight_g: (json['weight_g'] as num).toInt(),
    recorded_on: json['recorded_on'] as String,
    source: json['source'] as String,
  );
  Map<String,dynamic> toJson() => {
    'weight_g': weight_g,
    'recorded_on': recorded_on,
    'source': source,
  };
}

class WeightCreated {
  final String id;
  final int weight_g;
  final String recorded_on;
  final String source;
  final int pet_version;
  const WeightCreated({required this.id, required this.weight_g, required this.recorded_on, required this.source, required this.pet_version});
  factory WeightCreated.fromJson(Map<String,dynamic> json) => WeightCreated(
    id: json['id'] as String,
    weight_g: (json['weight_g'] as num).toInt(),
    recorded_on: json['recorded_on'] as String,
    source: json['source'] as String,
    pet_version: (json['pet_version'] as num).toInt(),
  );
  Map<String,dynamic> toJson() => {
    'id': id,
    'weight_g': weight_g,
    'recorded_on': recorded_on,
    'source': source,
    'pet_version': pet_version,
  };
}

class PetDeleted {
  final String id;
  final int version;
  final String status;
  const PetDeleted({required this.id, required this.version, required this.status});
  factory PetDeleted.fromJson(Map<String,dynamic> json) => PetDeleted(
    id: json['id'] as String,
    version: (json['version'] as num).toInt(),
    status: json['status'] as String,
  );
  Map<String,dynamic> toJson() => {
    'id': id,
    'version': version,
    'status': status,
  };
}

class TaxonomyCreated {
  final String id;
  final String name;
  const TaxonomyCreated({required this.id, required this.name});
  factory TaxonomyCreated.fromJson(Map<String,dynamic> json) => TaxonomyCreated(
    id: json['id'] as String,
    name: json['name'] as String,
  );
  Map<String,dynamic> toJson() => {
    'id': id,
    'name': name,
  };
}

class TaxonomyRetired {
  final String id;
  final String status;
  const TaxonomyRetired({required this.id, required this.status});
  factory TaxonomyRetired.fromJson(Map<String,dynamic> json) => TaxonomyRetired(
    id: json['id'] as String,
    status: json['status'] as String,
  );
  Map<String,dynamic> toJson() => {
    'id': id,
    'status': status,
  };
}

class RulePublished {
  final String id;
  final String species_id;
  final int version_no;
  final String status;
  const RulePublished({required this.id, required this.species_id, required this.version_no, required this.status});
  factory RulePublished.fromJson(Map<String,dynamic> json) => RulePublished(
    id: json['id'] as String,
    species_id: json['species_id'] as String,
    version_no: (json['version_no'] as num).toInt(),
    status: json['status'] as String,
  );
  Map<String,dynamic> toJson() => {
    'id': id,
    'species_id': species_id,
    'version_no': version_no,
    'status': status,
  };
}

class SpeciesCreate {
  final String name;
  final String parent_id;
  const SpeciesCreate({required this.name, required this.parent_id});
  factory SpeciesCreate.fromJson(Map<String,dynamic> json) => SpeciesCreate(
    name: json['name'] as String,
    parent_id: json['parent_id'] as String,
  );
  Map<String,dynamic> toJson() => {
    'name': name,
    'parent_id': parent_id,
  };
}

class BreedCreate {
  final String name;
  final String species_id;
  const BreedCreate({required this.name, required this.species_id});
  factory BreedCreate.fromJson(Map<String,dynamic> json) => BreedCreate(
    name: json['name'] as String,
    species_id: json['species_id'] as String,
  );
  Map<String,dynamic> toJson() => {
    'name': name,
    'species_id': species_id,
  };
}

class AllergenCreate {
  final String name;
  const AllergenCreate({required this.name});
  factory AllergenCreate.fromJson(Map<String,dynamic> json) => AllergenCreate(
    name: json['name'] as String,
  );
  Map<String,dynamic> toJson() => {
    'name': name,
  };
}

class StageDefinition {
  final String stage_code;
  final String display_name;
  final int? min_age_value;
  final int? max_age_value;
  final String age_unit;
  final bool is_unknown;
  const StageDefinition({required this.stage_code, required this.display_name, required this.min_age_value, required this.max_age_value, required this.age_unit, required this.is_unknown});
  factory StageDefinition.fromJson(Map<String,dynamic> json) => StageDefinition(
    stage_code: json['stage_code'] as String,
    display_name: json['display_name'] as String,
    min_age_value: json['min_age_value'] == null ? null : (json['min_age_value'] as num).toInt(),
    max_age_value: json['max_age_value'] == null ? null : (json['max_age_value'] as num).toInt(),
    age_unit: json['age_unit'] as String,
    is_unknown: json['is_unknown'] as bool,
  );
  Map<String,dynamic> toJson() => {
    'stage_code': stage_code,
    'display_name': display_name,
    'min_age_value': min_age_value == null ? null : min_age_value!,
    'max_age_value': max_age_value == null ? null : max_age_value!,
    'age_unit': age_unit,
    'is_unknown': is_unknown,
  };
}

class RulePublish {
  final String species_id;
  final List<String> source_refs;
  final List<StageDefinition> stages;
  const RulePublish({required this.species_id, required this.source_refs, required this.stages});
  factory RulePublish.fromJson(Map<String,dynamic> json) => RulePublish(
    species_id: json['species_id'] as String,
    source_refs: (json['source_refs'] as List).map((value) => value as String).toList(),
    stages: (json['stages'] as List).map((value) => StageDefinition.fromJson(Map<String,dynamic>.from(value as Map))).toList(),
  );
  Map<String,dynamic> toJson() => {
    'species_id': species_id,
    'source_refs': source_refs.map((value) => value).toList(),
    'stages': stages.map((value) => value.toJson()).toList(),
  };
}

class SpeciesListEnvelope {
  final List<Species> data;
  final Page page;
  final Meta meta;
  const SpeciesListEnvelope({required this.data, required this.page, required this.meta});
  factory SpeciesListEnvelope.fromJson(Map<String,dynamic> json) => SpeciesListEnvelope(
    data: (json['data'] as List).map((value) => Species.fromJson(Map<String,dynamic>.from(value as Map))).toList(),
    page: Page.fromJson(Map<String,dynamic>.from(json['page'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.map((value) => value.toJson()).toList(),
    'page': page.toJson(),
    'meta': meta.toJson(),
  };
}

class BreedListEnvelope {
  final List<Breed> data;
  final Page page;
  final Meta meta;
  const BreedListEnvelope({required this.data, required this.page, required this.meta});
  factory BreedListEnvelope.fromJson(Map<String,dynamic> json) => BreedListEnvelope(
    data: (json['data'] as List).map((value) => Breed.fromJson(Map<String,dynamic>.from(value as Map))).toList(),
    page: Page.fromJson(Map<String,dynamic>.from(json['page'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.map((value) => value.toJson()).toList(),
    'page': page.toJson(),
    'meta': meta.toJson(),
  };
}

class AllergenListEnvelope {
  final List<Allergen> data;
  final Page page;
  final Meta meta;
  const AllergenListEnvelope({required this.data, required this.page, required this.meta});
  factory AllergenListEnvelope.fromJson(Map<String,dynamic> json) => AllergenListEnvelope(
    data: (json['data'] as List).map((value) => Allergen.fromJson(Map<String,dynamic>.from(value as Map))).toList(),
    page: Page.fromJson(Map<String,dynamic>.from(json['page'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.map((value) => value.toJson()).toList(),
    'page': page.toJson(),
    'meta': meta.toJson(),
  };
}

class PetListEnvelope {
  final List<Pet> data;
  final Page page;
  final Meta meta;
  const PetListEnvelope({required this.data, required this.page, required this.meta});
  factory PetListEnvelope.fromJson(Map<String,dynamic> json) => PetListEnvelope(
    data: (json['data'] as List).map((value) => Pet.fromJson(Map<String,dynamic>.from(value as Map))).toList(),
    page: Page.fromJson(Map<String,dynamic>.from(json['page'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.map((value) => value.toJson()).toList(),
    'page': page.toJson(),
    'meta': meta.toJson(),
  };
}

class PetEnvelope {
  final Pet data;
  final Meta meta;
  const PetEnvelope({required this.data, required this.meta});
  factory PetEnvelope.fromJson(Map<String,dynamic> json) => PetEnvelope(
    data: Pet.fromJson(Map<String,dynamic>.from(json['data'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.toJson(),
    'meta': meta.toJson(),
  };
}

class PetDeletedEnvelope {
  final PetDeleted data;
  final Meta meta;
  const PetDeletedEnvelope({required this.data, required this.meta});
  factory PetDeletedEnvelope.fromJson(Map<String,dynamic> json) => PetDeletedEnvelope(
    data: PetDeleted.fromJson(Map<String,dynamic>.from(json['data'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.toJson(),
    'meta': meta.toJson(),
  };
}

class WeightListEnvelope {
  final List<Weight> data;
  final Page page;
  final Meta meta;
  const WeightListEnvelope({required this.data, required this.page, required this.meta});
  factory WeightListEnvelope.fromJson(Map<String,dynamic> json) => WeightListEnvelope(
    data: (json['data'] as List).map((value) => Weight.fromJson(Map<String,dynamic>.from(value as Map))).toList(),
    page: Page.fromJson(Map<String,dynamic>.from(json['page'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.map((value) => value.toJson()).toList(),
    'page': page.toJson(),
    'meta': meta.toJson(),
  };
}

class WeightCreatedEnvelope {
  final WeightCreated data;
  final Meta meta;
  const WeightCreatedEnvelope({required this.data, required this.meta});
  factory WeightCreatedEnvelope.fromJson(Map<String,dynamic> json) => WeightCreatedEnvelope(
    data: WeightCreated.fromJson(Map<String,dynamic>.from(json['data'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.toJson(),
    'meta': meta.toJson(),
  };
}

class TaxonomyCreatedEnvelope {
  final TaxonomyCreated data;
  final Meta meta;
  const TaxonomyCreatedEnvelope({required this.data, required this.meta});
  factory TaxonomyCreatedEnvelope.fromJson(Map<String,dynamic> json) => TaxonomyCreatedEnvelope(
    data: TaxonomyCreated.fromJson(Map<String,dynamic>.from(json['data'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.toJson(),
    'meta': meta.toJson(),
  };
}

class RulePublishedEnvelope {
  final RulePublished data;
  final Meta meta;
  const RulePublishedEnvelope({required this.data, required this.meta});
  factory RulePublishedEnvelope.fromJson(Map<String,dynamic> json) => RulePublishedEnvelope(
    data: RulePublished.fromJson(Map<String,dynamic>.from(json['data'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.toJson(),
    'meta': meta.toJson(),
  };
}

class TaxonomyRetiredEnvelope {
  final TaxonomyRetired data;
  final Meta meta;
  const TaxonomyRetiredEnvelope({required this.data, required this.meta});
  factory TaxonomyRetiredEnvelope.fromJson(Map<String,dynamic> json) => TaxonomyRetiredEnvelope(
    data: TaxonomyRetired.fromJson(Map<String,dynamic>.from(json['data'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.toJson(),
    'meta': meta.toJson(),
  };
}

class CatalogNutrient {
  final String name;
  final int value_milli;
  final String unit;
  final String basis;
  final String qualifier;
  const CatalogNutrient({required this.name, required this.value_milli, required this.unit, required this.basis, required this.qualifier});
  factory CatalogNutrient.fromJson(Map<String,dynamic> json) => CatalogNutrient(
    name: json['name'] as String,
    value_milli: (json['value_milli'] as num).toInt(),
    unit: json['unit'] as String,
    basis: json['basis'] as String,
    qualifier: json['qualifier'] as String,
  );
  Map<String,dynamic> toJson() => {
    'name': name,
    'value_milli': value_milli,
    'unit': unit,
    'basis': basis,
    'qualifier': qualifier,
  };
}

class CatalogStandardInput {
  final List<String> ingredients;
  final List<CatalogNutrient> nutrients;
  final List<String> allergen_ids;
  final bool allergens_known;
  final List<String> life_stage_ids;
  final List<String> source_refs;
  final String source_updated_on;
  const CatalogStandardInput({required this.ingredients, required this.nutrients, required this.allergen_ids, required this.allergens_known, required this.life_stage_ids, required this.source_refs, required this.source_updated_on});
  factory CatalogStandardInput.fromJson(Map<String,dynamic> json) => CatalogStandardInput(
    ingredients: (json['ingredients'] as List).map((value) => value as String).toList(),
    nutrients: (json['nutrients'] as List).map((value) => CatalogNutrient.fromJson(Map<String,dynamic>.from(value as Map))).toList(),
    allergen_ids: (json['allergen_ids'] as List).map((value) => value as String).toList(),
    allergens_known: json['allergens_known'] as bool,
    life_stage_ids: (json['life_stage_ids'] as List).map((value) => value as String).toList(),
    source_refs: (json['source_refs'] as List).map((value) => value as String).toList(),
    source_updated_on: json['source_updated_on'] as String,
  );
  Map<String,dynamic> toJson() => {
    'ingredients': ingredients.map((value) => value).toList(),
    'nutrients': nutrients.map((value) => value.toJson()).toList(),
    'allergen_ids': allergen_ids.map((value) => value).toList(),
    'allergens_known': allergens_known,
    'life_stage_ids': life_stage_ids.map((value) => value).toList(),
    'source_refs': source_refs.map((value) => value).toList(),
    'source_updated_on': source_updated_on,
  };
}

class CatalogBrandInput {
  final String name;
  final String source_ref;
  const CatalogBrandInput({required this.name, required this.source_ref});
  factory CatalogBrandInput.fromJson(Map<String,dynamic> json) => CatalogBrandInput(
    name: json['name'] as String,
    source_ref: json['source_ref'] as String,
  );
  Map<String,dynamic> toJson() => {
    'name': name,
    'source_ref': source_ref,
  };
}

class CatalogSpuInput {
  final String brand_id;
  final String name;
  final String pet_category;
  final String category;
  const CatalogSpuInput({required this.brand_id, required this.name, required this.pet_category, required this.category});
  factory CatalogSpuInput.fromJson(Map<String,dynamic> json) => CatalogSpuInput(
    brand_id: json['brand_id'] as String,
    name: json['name'] as String,
    pet_category: json['pet_category'] as String,
    category: json['category'] as String,
  );
  Map<String,dynamic> toJson() => {
    'brand_id': brand_id,
    'name': name,
    'pet_category': pet_category,
    'category': category,
  };
}

class CatalogSkuInput {
  final String spu_id;
  final String sku_code;
  final String? barcode;
  final int weight_g;
  final String package_unit;
  const CatalogSkuInput({required this.spu_id, required this.sku_code, required this.barcode, required this.weight_g, required this.package_unit});
  factory CatalogSkuInput.fromJson(Map<String,dynamic> json) => CatalogSkuInput(
    spu_id: json['spu_id'] as String,
    sku_code: json['sku_code'] as String,
    barcode: json['barcode'] == null ? null : json['barcode'] as String,
    weight_g: (json['weight_g'] as num).toInt(),
    package_unit: json['package_unit'] as String,
  );
  Map<String,dynamic> toJson() => {
    'spu_id': spu_id,
    'sku_code': sku_code,
    'barcode': barcode == null ? null : barcode!,
    'weight_g': weight_g,
    'package_unit': package_unit,
  };
}

class CatalogCreated {
  final String id;
  final String status;
  const CatalogCreated({required this.id, required this.status});
  factory CatalogCreated.fromJson(Map<String,dynamic> json) => CatalogCreated(
    id: json['id'] as String,
    status: json['status'] as String,
  );
  Map<String,dynamic> toJson() => {
    'id': id,
    'status': status,
  };
}

class CatalogBrand {
  final String id;
  final String name;
  final String source_ref;
  final String status;
  const CatalogBrand({required this.id, required this.name, required this.source_ref, required this.status});
  factory CatalogBrand.fromJson(Map<String,dynamic> json) => CatalogBrand(
    id: json['id'] as String,
    name: json['name'] as String,
    source_ref: json['source_ref'] as String,
    status: json['status'] as String,
  );
  Map<String,dynamic> toJson() => {
    'id': id,
    'name': name,
    'source_ref': source_ref,
    'status': status,
  };
}

class CatalogSpu {
  final String id;
  final String brand_id;
  final String name;
  final String pet_category;
  final String category;
  final String status;
  const CatalogSpu({required this.id, required this.brand_id, required this.name, required this.pet_category, required this.category, required this.status});
  factory CatalogSpu.fromJson(Map<String,dynamic> json) => CatalogSpu(
    id: json['id'] as String,
    brand_id: json['brand_id'] as String,
    name: json['name'] as String,
    pet_category: json['pet_category'] as String,
    category: json['category'] as String,
    status: json['status'] as String,
  );
  Map<String,dynamic> toJson() => {
    'id': id,
    'brand_id': brand_id,
    'name': name,
    'pet_category': pet_category,
    'category': category,
    'status': status,
  };
}

class CatalogSku {
  final String id;
  final String spu_id;
  final String sku_code;
  final String? barcode;
  final int weight_g;
  final String package_unit;
  final String status;
  final int version;
  const CatalogSku({required this.id, required this.spu_id, required this.sku_code, required this.barcode, required this.weight_g, required this.package_unit, required this.status, required this.version});
  factory CatalogSku.fromJson(Map<String,dynamic> json) => CatalogSku(
    id: json['id'] as String,
    spu_id: json['spu_id'] as String,
    sku_code: json['sku_code'] as String,
    barcode: json['barcode'] == null ? null : json['barcode'] as String,
    weight_g: (json['weight_g'] as num).toInt(),
    package_unit: json['package_unit'] as String,
    status: json['status'] as String,
    version: (json['version'] as num).toInt(),
  );
  Map<String,dynamic> toJson() => {
    'id': id,
    'spu_id': spu_id,
    'sku_code': sku_code,
    'barcode': barcode == null ? null : barcode!,
    'weight_g': weight_g,
    'package_unit': package_unit,
    'status': status,
    'version': version,
  };
}

class CatalogStandard {
  final String id;
  final String sku_id;
  final int version_no;
  final String status;
  final List<String> ingredients;
  final List<CatalogNutrient> nutrients;
  final List<String> allergen_ids;
  final bool allergens_known;
  final List<String> life_stage_ids;
  final List<String> source_refs;
  final String source_updated_on;
  final String created_by;
  final String created_at;
  final String? published_at;
  const CatalogStandard({required this.id, required this.sku_id, required this.version_no, required this.status, required this.ingredients, required this.nutrients, required this.allergen_ids, required this.allergens_known, required this.life_stage_ids, required this.source_refs, required this.source_updated_on, required this.created_by, required this.created_at, required this.published_at});
  factory CatalogStandard.fromJson(Map<String,dynamic> json) => CatalogStandard(
    id: json['id'] as String,
    sku_id: json['sku_id'] as String,
    version_no: (json['version_no'] as num).toInt(),
    status: json['status'] as String,
    ingredients: (json['ingredients'] as List).map((value) => value as String).toList(),
    nutrients: (json['nutrients'] as List).map((value) => CatalogNutrient.fromJson(Map<String,dynamic>.from(value as Map))).toList(),
    allergen_ids: (json['allergen_ids'] as List).map((value) => value as String).toList(),
    allergens_known: json['allergens_known'] as bool,
    life_stage_ids: (json['life_stage_ids'] as List).map((value) => value as String).toList(),
    source_refs: (json['source_refs'] as List).map((value) => value as String).toList(),
    source_updated_on: json['source_updated_on'] as String,
    created_by: json['created_by'] as String,
    created_at: json['created_at'] as String,
    published_at: json['published_at'] == null ? null : json['published_at'] as String,
  );
  Map<String,dynamic> toJson() => {
    'id': id,
    'sku_id': sku_id,
    'version_no': version_no,
    'status': status,
    'ingredients': ingredients.map((value) => value).toList(),
    'nutrients': nutrients.map((value) => value.toJson()).toList(),
    'allergen_ids': allergen_ids.map((value) => value).toList(),
    'allergens_known': allergens_known,
    'life_stage_ids': life_stage_ids.map((value) => value).toList(),
    'source_refs': source_refs.map((value) => value).toList(),
    'source_updated_on': source_updated_on,
    'created_by': created_by,
    'created_at': created_at,
    'published_at': published_at == null ? null : published_at!,
  };
}

class CatalogSkuDetail {
  final String id;
  final String spu_id;
  final String sku_code;
  final String? barcode;
  final int weight_g;
  final String package_unit;
  final String status;
  final int version;
  final List<CatalogStandard> standard_versions;
  const CatalogSkuDetail({required this.id, required this.spu_id, required this.sku_code, required this.barcode, required this.weight_g, required this.package_unit, required this.status, required this.version, required this.standard_versions});
  factory CatalogSkuDetail.fromJson(Map<String,dynamic> json) => CatalogSkuDetail(
    id: json['id'] as String,
    spu_id: json['spu_id'] as String,
    sku_code: json['sku_code'] as String,
    barcode: json['barcode'] == null ? null : json['barcode'] as String,
    weight_g: (json['weight_g'] as num).toInt(),
    package_unit: json['package_unit'] as String,
    status: json['status'] as String,
    version: (json['version'] as num).toInt(),
    standard_versions: (json['standard_versions'] as List).map((value) => CatalogStandard.fromJson(Map<String,dynamic>.from(value as Map))).toList(),
  );
  Map<String,dynamic> toJson() => {
    'id': id,
    'spu_id': spu_id,
    'sku_code': sku_code,
    'barcode': barcode == null ? null : barcode!,
    'weight_g': weight_g,
    'package_unit': package_unit,
    'status': status,
    'version': version,
    'standard_versions': standard_versions.map((value) => value.toJson()).toList(),
  };
}

class CatalogDrafted {
  final String id;
  final String sku_id;
  final int version_no;
  final String status;
  final int sku_version;
  const CatalogDrafted({required this.id, required this.sku_id, required this.version_no, required this.status, required this.sku_version});
  factory CatalogDrafted.fromJson(Map<String,dynamic> json) => CatalogDrafted(
    id: json['id'] as String,
    sku_id: json['sku_id'] as String,
    version_no: (json['version_no'] as num).toInt(),
    status: json['status'] as String,
    sku_version: (json['sku_version'] as num).toInt(),
  );
  Map<String,dynamic> toJson() => {
    'id': id,
    'sku_id': sku_id,
    'version_no': version_no,
    'status': status,
    'sku_version': sku_version,
  };
}

class CatalogPublished {
  final String id;
  final String sku_id;
  final String status;
  final int sku_version;
  const CatalogPublished({required this.id, required this.sku_id, required this.status, required this.sku_version});
  factory CatalogPublished.fromJson(Map<String,dynamic> json) => CatalogPublished(
    id: json['id'] as String,
    sku_id: json['sku_id'] as String,
    status: json['status'] as String,
    sku_version: (json['sku_version'] as num).toInt(),
  );
  Map<String,dynamic> toJson() => {
    'id': id,
    'sku_id': sku_id,
    'status': status,
    'sku_version': sku_version,
  };
}

class CatalogCorrectionInput {
  final String sku_id;
  final int base_sku_version;
  final String reason;
  final CatalogStandardInput standard;
  const CatalogCorrectionInput({required this.sku_id, required this.base_sku_version, required this.reason, required this.standard});
  factory CatalogCorrectionInput.fromJson(Map<String,dynamic> json) => CatalogCorrectionInput(
    sku_id: json['sku_id'] as String,
    base_sku_version: (json['base_sku_version'] as num).toInt(),
    reason: json['reason'] as String,
    standard: CatalogStandardInput.fromJson(Map<String,dynamic>.from(json['standard'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'sku_id': sku_id,
    'base_sku_version': base_sku_version,
    'reason': reason,
    'standard': standard.toJson(),
  };
}

class CatalogRequestCreated {
  final String id;
  final String status;
  final int version;
  const CatalogRequestCreated({required this.id, required this.status, required this.version});
  factory CatalogRequestCreated.fromJson(Map<String,dynamic> json) => CatalogRequestCreated(
    id: json['id'] as String,
    status: json['status'] as String,
    version: (json['version'] as num).toInt(),
  );
  Map<String,dynamic> toJson() => {
    'id': id,
    'status': status,
    'version': version,
  };
}

class CatalogReviewInput {
  final String reason;
  const CatalogReviewInput({required this.reason});
  factory CatalogReviewInput.fromJson(Map<String,dynamic> json) => CatalogReviewInput(
    reason: json['reason'] as String,
  );
  Map<String,dynamic> toJson() => {
    'reason': reason,
  };
}

class CatalogReviewed {
  final String id;
  final String status;
  final int version;
  const CatalogReviewed({required this.id, required this.status, required this.version});
  factory CatalogReviewed.fromJson(Map<String,dynamic> json) => CatalogReviewed(
    id: json['id'] as String,
    status: json['status'] as String,
    version: (json['version'] as num).toInt(),
  );
  Map<String,dynamic> toJson() => {
    'id': id,
    'status': status,
    'version': version,
  };
}

class CatalogReview {
  final String id;
  final String request_id;
  final String reviewer_id;
  final String decision;
  final String reason;
  final String created_at;
  const CatalogReview({required this.id, required this.request_id, required this.reviewer_id, required this.decision, required this.reason, required this.created_at});
  factory CatalogReview.fromJson(Map<String,dynamic> json) => CatalogReview(
    id: json['id'] as String,
    request_id: json['request_id'] as String,
    reviewer_id: json['reviewer_id'] as String,
    decision: json['decision'] as String,
    reason: json['reason'] as String,
    created_at: json['created_at'] as String,
  );
  Map<String,dynamic> toJson() => {
    'id': id,
    'request_id': request_id,
    'reviewer_id': reviewer_id,
    'decision': decision,
    'reason': reason,
    'created_at': created_at,
  };
}

class CatalogRequest {
  final String id;
  final String merchant_id;
  final String submitted_by;
  final String sku_id;
  final int base_sku_version;
  final CatalogStandardInput proposal;
  final String reason;
  final String status;
  final int version;
  final String? result_version_id;
  final String created_at;
  final List<CatalogReview> reviews;
  const CatalogRequest({required this.id, required this.merchant_id, required this.submitted_by, required this.sku_id, required this.base_sku_version, required this.proposal, required this.reason, required this.status, required this.version, required this.result_version_id, required this.created_at, required this.reviews});
  factory CatalogRequest.fromJson(Map<String,dynamic> json) => CatalogRequest(
    id: json['id'] as String,
    merchant_id: json['merchant_id'] as String,
    submitted_by: json['submitted_by'] as String,
    sku_id: json['sku_id'] as String,
    base_sku_version: (json['base_sku_version'] as num).toInt(),
    proposal: CatalogStandardInput.fromJson(Map<String,dynamic>.from(json['proposal'] as Map)),
    reason: json['reason'] as String,
    status: json['status'] as String,
    version: (json['version'] as num).toInt(),
    result_version_id: json['result_version_id'] == null ? null : json['result_version_id'] as String,
    created_at: json['created_at'] as String,
    reviews: (json['reviews'] as List).map((value) => CatalogReview.fromJson(Map<String,dynamic>.from(value as Map))).toList(),
  );
  Map<String,dynamic> toJson() => {
    'id': id,
    'merchant_id': merchant_id,
    'submitted_by': submitted_by,
    'sku_id': sku_id,
    'base_sku_version': base_sku_version,
    'proposal': proposal.toJson(),
    'reason': reason,
    'status': status,
    'version': version,
    'result_version_id': result_version_id == null ? null : result_version_id!,
    'created_at': created_at,
    'reviews': reviews.map((value) => value.toJson()).toList(),
  };
}

class CatalogImportInput {
  final String format;
  final String content_base64;
  const CatalogImportInput({required this.format, required this.content_base64});
  factory CatalogImportInput.fromJson(Map<String,dynamic> json) => CatalogImportInput(
    format: json['format'] as String,
    content_base64: json['content_base64'] as String,
  );
  Map<String,dynamic> toJson() => {
    'format': format,
    'content_base64': content_base64,
  };
}

class CatalogImportRow {
  final String batch_id;
  final int row_no;
  final Map<String,dynamic> payload;
  final List<String> error_codes;
  final int? base_sku_version;
  final String? result_version_id;
  const CatalogImportRow({required this.batch_id, required this.row_no, required this.payload, required this.error_codes, required this.base_sku_version, required this.result_version_id});
  factory CatalogImportRow.fromJson(Map<String,dynamic> json) => CatalogImportRow(
    batch_id: json['batch_id'] as String,
    row_no: (json['row_no'] as num).toInt(),
    payload: Map<String,dynamic>.from(json['payload'] as Map),
    error_codes: (json['error_codes'] as List).map((value) => value as String).toList(),
    base_sku_version: json['base_sku_version'] == null ? null : (json['base_sku_version'] as num).toInt(),
    result_version_id: json['result_version_id'] == null ? null : json['result_version_id'] as String,
  );
  Map<String,dynamic> toJson() => {
    'batch_id': batch_id,
    'row_no': row_no,
    'payload': payload,
    'error_codes': error_codes.map((value) => value).toList(),
    'base_sku_version': base_sku_version == null ? null : base_sku_version!,
    'result_version_id': result_version_id == null ? null : result_version_id!,
  };
}

class CatalogImport {
  final String id;
  final String created_by;
  final String format;
  final String status;
  final int version;
  final String created_at;
  final List<CatalogImportRow> rows;
  const CatalogImport({required this.id, required this.created_by, required this.format, required this.status, required this.version, required this.created_at, required this.rows});
  factory CatalogImport.fromJson(Map<String,dynamic> json) => CatalogImport(
    id: json['id'] as String,
    created_by: json['created_by'] as String,
    format: json['format'] as String,
    status: json['status'] as String,
    version: (json['version'] as num).toInt(),
    created_at: json['created_at'] as String,
    rows: (json['rows'] as List).map((value) => CatalogImportRow.fromJson(Map<String,dynamic>.from(value as Map))).toList(),
  );
  Map<String,dynamic> toJson() => {
    'id': id,
    'created_by': created_by,
    'format': format,
    'status': status,
    'version': version,
    'created_at': created_at,
    'rows': rows.map((value) => value.toJson()).toList(),
  };
}

class CatalogImportFinished {
  final String id;
  final String status;
  final int version;
  const CatalogImportFinished({required this.id, required this.status, required this.version});
  factory CatalogImportFinished.fromJson(Map<String,dynamic> json) => CatalogImportFinished(
    id: json['id'] as String,
    status: json['status'] as String,
    version: (json['version'] as num).toInt(),
  );
  Map<String,dynamic> toJson() => {
    'id': id,
    'status': status,
    'version': version,
  };
}

class CatalogBrandListEnvelope {
  final List<CatalogBrand> data;
  final Page page;
  final Meta meta;
  const CatalogBrandListEnvelope({required this.data, required this.page, required this.meta});
  factory CatalogBrandListEnvelope.fromJson(Map<String,dynamic> json) => CatalogBrandListEnvelope(
    data: (json['data'] as List).map((value) => CatalogBrand.fromJson(Map<String,dynamic>.from(value as Map))).toList(),
    page: Page.fromJson(Map<String,dynamic>.from(json['page'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.map((value) => value.toJson()).toList(),
    'page': page.toJson(),
    'meta': meta.toJson(),
  };
}

class CatalogCreatedEnvelope {
  final CatalogCreated data;
  final Meta meta;
  const CatalogCreatedEnvelope({required this.data, required this.meta});
  factory CatalogCreatedEnvelope.fromJson(Map<String,dynamic> json) => CatalogCreatedEnvelope(
    data: CatalogCreated.fromJson(Map<String,dynamic>.from(json['data'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.toJson(),
    'meta': meta.toJson(),
  };
}

class CatalogSpuListEnvelope {
  final List<CatalogSpu> data;
  final Page page;
  final Meta meta;
  const CatalogSpuListEnvelope({required this.data, required this.page, required this.meta});
  factory CatalogSpuListEnvelope.fromJson(Map<String,dynamic> json) => CatalogSpuListEnvelope(
    data: (json['data'] as List).map((value) => CatalogSpu.fromJson(Map<String,dynamic>.from(value as Map))).toList(),
    page: Page.fromJson(Map<String,dynamic>.from(json['page'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.map((value) => value.toJson()).toList(),
    'page': page.toJson(),
    'meta': meta.toJson(),
  };
}

class CatalogSkuListEnvelope {
  final List<CatalogSku> data;
  final Page page;
  final Meta meta;
  const CatalogSkuListEnvelope({required this.data, required this.page, required this.meta});
  factory CatalogSkuListEnvelope.fromJson(Map<String,dynamic> json) => CatalogSkuListEnvelope(
    data: (json['data'] as List).map((value) => CatalogSku.fromJson(Map<String,dynamic>.from(value as Map))).toList(),
    page: Page.fromJson(Map<String,dynamic>.from(json['page'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.map((value) => value.toJson()).toList(),
    'page': page.toJson(),
    'meta': meta.toJson(),
  };
}

class CatalogSkuDetailEnvelope {
  final CatalogSkuDetail data;
  final Meta meta;
  const CatalogSkuDetailEnvelope({required this.data, required this.meta});
  factory CatalogSkuDetailEnvelope.fromJson(Map<String,dynamic> json) => CatalogSkuDetailEnvelope(
    data: CatalogSkuDetail.fromJson(Map<String,dynamic>.from(json['data'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.toJson(),
    'meta': meta.toJson(),
  };
}

class CatalogDraftedEnvelope {
  final CatalogDrafted data;
  final Meta meta;
  const CatalogDraftedEnvelope({required this.data, required this.meta});
  factory CatalogDraftedEnvelope.fromJson(Map<String,dynamic> json) => CatalogDraftedEnvelope(
    data: CatalogDrafted.fromJson(Map<String,dynamic>.from(json['data'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.toJson(),
    'meta': meta.toJson(),
  };
}

class CatalogPublishedEnvelope {
  final CatalogPublished data;
  final Meta meta;
  const CatalogPublishedEnvelope({required this.data, required this.meta});
  factory CatalogPublishedEnvelope.fromJson(Map<String,dynamic> json) => CatalogPublishedEnvelope(
    data: CatalogPublished.fromJson(Map<String,dynamic>.from(json['data'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.toJson(),
    'meta': meta.toJson(),
  };
}

class CatalogRequestCreatedEnvelope {
  final CatalogRequestCreated data;
  final Meta meta;
  const CatalogRequestCreatedEnvelope({required this.data, required this.meta});
  factory CatalogRequestCreatedEnvelope.fromJson(Map<String,dynamic> json) => CatalogRequestCreatedEnvelope(
    data: CatalogRequestCreated.fromJson(Map<String,dynamic>.from(json['data'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.toJson(),
    'meta': meta.toJson(),
  };
}

class CatalogRequestListEnvelope {
  final List<CatalogRequest> data;
  final Page page;
  final Meta meta;
  const CatalogRequestListEnvelope({required this.data, required this.page, required this.meta});
  factory CatalogRequestListEnvelope.fromJson(Map<String,dynamic> json) => CatalogRequestListEnvelope(
    data: (json['data'] as List).map((value) => CatalogRequest.fromJson(Map<String,dynamic>.from(value as Map))).toList(),
    page: Page.fromJson(Map<String,dynamic>.from(json['page'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.map((value) => value.toJson()).toList(),
    'page': page.toJson(),
    'meta': meta.toJson(),
  };
}

class CatalogRequestEnvelope {
  final CatalogRequest data;
  final Meta meta;
  const CatalogRequestEnvelope({required this.data, required this.meta});
  factory CatalogRequestEnvelope.fromJson(Map<String,dynamic> json) => CatalogRequestEnvelope(
    data: CatalogRequest.fromJson(Map<String,dynamic>.from(json['data'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.toJson(),
    'meta': meta.toJson(),
  };
}

class CatalogReviewedEnvelope {
  final CatalogReviewed data;
  final Meta meta;
  const CatalogReviewedEnvelope({required this.data, required this.meta});
  factory CatalogReviewedEnvelope.fromJson(Map<String,dynamic> json) => CatalogReviewedEnvelope(
    data: CatalogReviewed.fromJson(Map<String,dynamic>.from(json['data'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.toJson(),
    'meta': meta.toJson(),
  };
}

class CatalogImportEnvelope {
  final CatalogImport data;
  final Meta meta;
  const CatalogImportEnvelope({required this.data, required this.meta});
  factory CatalogImportEnvelope.fromJson(Map<String,dynamic> json) => CatalogImportEnvelope(
    data: CatalogImport.fromJson(Map<String,dynamic>.from(json['data'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.toJson(),
    'meta': meta.toJson(),
  };
}

class CatalogImportFinishedEnvelope {
  final CatalogImportFinished data;
  final Meta meta;
  const CatalogImportFinishedEnvelope({required this.data, required this.meta});
  factory CatalogImportFinishedEnvelope.fromJson(Map<String,dynamic> json) => CatalogImportFinishedEnvelope(
    data: CatalogImportFinished.fromJson(Map<String,dynamic>.from(json['data'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.toJson(),
    'meta': meta.toJson(),
  };
}

class OfferPriceChanges {
  final int? sale_price_fen;
  final int? member_price_fen;
  final String? fulfillment_sla;
  const OfferPriceChanges({this.sale_price_fen, this.member_price_fen, this.fulfillment_sla});
  factory OfferPriceChanges.fromJson(Map<String,dynamic> json) => OfferPriceChanges(
    sale_price_fen: json['sale_price_fen'] == null ? null : (json['sale_price_fen'] as num).toInt(),
    member_price_fen: json['member_price_fen'] == null ? null : (json['member_price_fen'] as num).toInt(),
    fulfillment_sla: json['fulfillment_sla'] == null ? null : json['fulfillment_sla'] as String,
  );
  Map<String,dynamic> toJson() => {
    if (sale_price_fen != null) 'sale_price_fen': sale_price_fen == null ? null : sale_price_fen!,
    if (member_price_fen != null) 'member_price_fen': member_price_fen == null ? null : member_price_fen!,
    if (fulfillment_sla != null) 'fulfillment_sla': fulfillment_sla == null ? null : fulfillment_sla!,
  };
}

class OfferCreateInput {
  final String? store_id;
  final String sku_id;
  final int sale_price_fen;
  final int? member_price_fen;
  final String fulfillment_sla;
  const OfferCreateInput({required this.store_id, required this.sku_id, required this.sale_price_fen, required this.member_price_fen, required this.fulfillment_sla});
  factory OfferCreateInput.fromJson(Map<String,dynamic> json) => OfferCreateInput(
    store_id: json['store_id'] == null ? null : json['store_id'] as String,
    sku_id: json['sku_id'] as String,
    sale_price_fen: (json['sale_price_fen'] as num).toInt(),
    member_price_fen: json['member_price_fen'] == null ? null : (json['member_price_fen'] as num).toInt(),
    fulfillment_sla: json['fulfillment_sla'] as String,
  );
  Map<String,dynamic> toJson() => {
    'store_id': store_id == null ? null : store_id!,
    'sku_id': sku_id,
    'sale_price_fen': sale_price_fen,
    'member_price_fen': member_price_fen == null ? null : member_price_fen!,
    'fulfillment_sla': fulfillment_sla,
  };
}

class OfferInventory {
  final String offer_id;
  final int on_hand_qty;
  final int reserved_qty;
  final int available_qty;
  final int version;
  final String updated_at;
  const OfferInventory({required this.offer_id, required this.on_hand_qty, required this.reserved_qty, required this.available_qty, required this.version, required this.updated_at});
  factory OfferInventory.fromJson(Map<String,dynamic> json) => OfferInventory(
    offer_id: json['offer_id'] as String,
    on_hand_qty: (json['on_hand_qty'] as num).toInt(),
    reserved_qty: (json['reserved_qty'] as num).toInt(),
    available_qty: (json['available_qty'] as num).toInt(),
    version: (json['version'] as num).toInt(),
    updated_at: json['updated_at'] as String,
  );
  Map<String,dynamic> toJson() => {
    'offer_id': offer_id,
    'on_hand_qty': on_hand_qty,
    'reserved_qty': reserved_qty,
    'available_qty': available_qty,
    'version': version,
    'updated_at': updated_at,
  };
}

class ManagedOffer {
  final String id;
  final String merchant_id;
  final String? store_id;
  final String sku_id;
  final int sale_price_fen;
  final int? member_price_fen;
  final String fulfillment_sla;
  final String sku_code;
  final String merchant_name;
  final String? store_name;
  final String sale_status;
  final int version;
  final String created_at;
  final String updated_at;
  final OfferInventory inventory;
  const ManagedOffer({required this.id, required this.merchant_id, required this.store_id, required this.sku_id, required this.sale_price_fen, required this.member_price_fen, required this.fulfillment_sla, required this.sku_code, required this.merchant_name, required this.store_name, required this.sale_status, required this.version, required this.created_at, required this.updated_at, required this.inventory});
  factory ManagedOffer.fromJson(Map<String,dynamic> json) => ManagedOffer(
    id: json['id'] as String,
    merchant_id: json['merchant_id'] as String,
    store_id: json['store_id'] == null ? null : json['store_id'] as String,
    sku_id: json['sku_id'] as String,
    sale_price_fen: (json['sale_price_fen'] as num).toInt(),
    member_price_fen: json['member_price_fen'] == null ? null : (json['member_price_fen'] as num).toInt(),
    fulfillment_sla: json['fulfillment_sla'] as String,
    sku_code: json['sku_code'] as String,
    merchant_name: json['merchant_name'] as String,
    store_name: json['store_name'] == null ? null : json['store_name'] as String,
    sale_status: json['sale_status'] as String,
    version: (json['version'] as num).toInt(),
    created_at: json['created_at'] as String,
    updated_at: json['updated_at'] as String,
    inventory: OfferInventory.fromJson(Map<String,dynamic>.from(json['inventory'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'id': id,
    'merchant_id': merchant_id,
    'store_id': store_id == null ? null : store_id!,
    'sku_id': sku_id,
    'sale_price_fen': sale_price_fen,
    'member_price_fen': member_price_fen == null ? null : member_price_fen!,
    'fulfillment_sla': fulfillment_sla,
    'sku_code': sku_code,
    'merchant_name': merchant_name,
    'store_name': store_name == null ? null : store_name!,
    'sale_status': sale_status,
    'version': version,
    'created_at': created_at,
    'updated_at': updated_at,
    'inventory': inventory.toJson(),
  };
}

class OfferStateInput {
  final String reason;
  const OfferStateInput({required this.reason});
  factory OfferStateInput.fromJson(Map<String,dynamic> json) => OfferStateInput(
    reason: json['reason'] as String,
  );
  Map<String,dynamic> toJson() => {
    'reason': reason,
  };
}

class InventoryAdjustmentInput {
  final int delta_qty;
  final String reason_code;
  final int expected_version;
  const InventoryAdjustmentInput({required this.delta_qty, required this.reason_code, required this.expected_version});
  factory InventoryAdjustmentInput.fromJson(Map<String,dynamic> json) => InventoryAdjustmentInput(
    delta_qty: (json['delta_qty'] as num).toInt(),
    reason_code: json['reason_code'] as String,
    expected_version: (json['expected_version'] as num).toInt(),
  );
  Map<String,dynamic> toJson() => {
    'delta_qty': delta_qty,
    'reason_code': reason_code,
    'expected_version': expected_version,
  };
}

class InventoryAdjustmentResult {
  final String adjustment_id;
  final String offer_id;
  final int delta_qty;
  final int resulting_on_hand_qty;
  final int resulting_reserved_qty;
  final int resulting_available_qty;
  final int version;
  const InventoryAdjustmentResult({required this.adjustment_id, required this.offer_id, required this.delta_qty, required this.resulting_on_hand_qty, required this.resulting_reserved_qty, required this.resulting_available_qty, required this.version});
  factory InventoryAdjustmentResult.fromJson(Map<String,dynamic> json) => InventoryAdjustmentResult(
    adjustment_id: json['adjustment_id'] as String,
    offer_id: json['offer_id'] as String,
    delta_qty: (json['delta_qty'] as num).toInt(),
    resulting_on_hand_qty: (json['resulting_on_hand_qty'] as num).toInt(),
    resulting_reserved_qty: (json['resulting_reserved_qty'] as num).toInt(),
    resulting_available_qty: (json['resulting_available_qty'] as num).toInt(),
    version: (json['version'] as num).toInt(),
  );
  Map<String,dynamic> toJson() => {
    'adjustment_id': adjustment_id,
    'offer_id': offer_id,
    'delta_qty': delta_qty,
    'resulting_on_hand_qty': resulting_on_hand_qty,
    'resulting_reserved_qty': resulting_reserved_qty,
    'resulting_available_qty': resulting_available_qty,
    'version': version,
  };
}

class InventoryAdjustmentRecord {
  final String id;
  final String offer_id;
  final int delta_qty;
  final String reason_code;
  final int expected_version;
  final int before_on_hand_qty;
  final int resulting_on_hand_qty;
  final int resulting_reserved_qty;
  final int resulting_version;
  final String actor_id;
  final String created_at;
  const InventoryAdjustmentRecord({required this.id, required this.offer_id, required this.delta_qty, required this.reason_code, required this.expected_version, required this.before_on_hand_qty, required this.resulting_on_hand_qty, required this.resulting_reserved_qty, required this.resulting_version, required this.actor_id, required this.created_at});
  factory InventoryAdjustmentRecord.fromJson(Map<String,dynamic> json) => InventoryAdjustmentRecord(
    id: json['id'] as String,
    offer_id: json['offer_id'] as String,
    delta_qty: (json['delta_qty'] as num).toInt(),
    reason_code: json['reason_code'] as String,
    expected_version: (json['expected_version'] as num).toInt(),
    before_on_hand_qty: (json['before_on_hand_qty'] as num).toInt(),
    resulting_on_hand_qty: (json['resulting_on_hand_qty'] as num).toInt(),
    resulting_reserved_qty: (json['resulting_reserved_qty'] as num).toInt(),
    resulting_version: (json['resulting_version'] as num).toInt(),
    actor_id: json['actor_id'] as String,
    created_at: json['created_at'] as String,
  );
  Map<String,dynamic> toJson() => {
    'id': id,
    'offer_id': offer_id,
    'delta_qty': delta_qty,
    'reason_code': reason_code,
    'expected_version': expected_version,
    'before_on_hand_qty': before_on_hand_qty,
    'resulting_on_hand_qty': resulting_on_hand_qty,
    'resulting_reserved_qty': resulting_reserved_qty,
    'resulting_version': resulting_version,
    'actor_id': actor_id,
    'created_at': created_at,
  };
}

class OfferBatchItem {
  final String offer_id;
  final int expected_version;
  final OfferPriceChanges changes;
  const OfferBatchItem({required this.offer_id, required this.expected_version, required this.changes});
  factory OfferBatchItem.fromJson(Map<String,dynamic> json) => OfferBatchItem(
    offer_id: json['offer_id'] as String,
    expected_version: (json['expected_version'] as num).toInt(),
    changes: OfferPriceChanges.fromJson(Map<String,dynamic>.from(json['changes'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'offer_id': offer_id,
    'expected_version': expected_version,
    'changes': changes.toJson(),
  };
}

class OfferBatchInput {
  final List<OfferBatchItem> items;
  const OfferBatchInput({required this.items});
  factory OfferBatchInput.fromJson(Map<String,dynamic> json) => OfferBatchInput(
    items: (json['items'] as List).map((value) => OfferBatchItem.fromJson(Map<String,dynamic>.from(value as Map))).toList(),
  );
  Map<String,dynamic> toJson() => {
    'items': items.map((value) => value.toJson()).toList(),
  };
}

class OfferBatchResult {
  final List<ManagedOffer> items;
  const OfferBatchResult({required this.items});
  factory OfferBatchResult.fromJson(Map<String,dynamic> json) => OfferBatchResult(
    items: (json['items'] as List).map((value) => ManagedOffer.fromJson(Map<String,dynamic>.from(value as Map))).toList(),
  );
  Map<String,dynamic> toJson() => {
    'items': items.map((value) => value.toJson()).toList(),
  };
}

class ManagedOfferListEnvelope {
  final List<ManagedOffer> data;
  final Page page;
  final Meta meta;
  const ManagedOfferListEnvelope({required this.data, required this.page, required this.meta});
  factory ManagedOfferListEnvelope.fromJson(Map<String,dynamic> json) => ManagedOfferListEnvelope(
    data: (json['data'] as List).map((value) => ManagedOffer.fromJson(Map<String,dynamic>.from(value as Map))).toList(),
    page: Page.fromJson(Map<String,dynamic>.from(json['page'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.map((value) => value.toJson()).toList(),
    'page': page.toJson(),
    'meta': meta.toJson(),
  };
}

class ManagedOfferEnvelope {
  final ManagedOffer data;
  final Meta meta;
  const ManagedOfferEnvelope({required this.data, required this.meta});
  factory ManagedOfferEnvelope.fromJson(Map<String,dynamic> json) => ManagedOfferEnvelope(
    data: ManagedOffer.fromJson(Map<String,dynamic>.from(json['data'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.toJson(),
    'meta': meta.toJson(),
  };
}

class InventoryAdjustmentRecordListEnvelope {
  final List<InventoryAdjustmentRecord> data;
  final Page page;
  final Meta meta;
  const InventoryAdjustmentRecordListEnvelope({required this.data, required this.page, required this.meta});
  factory InventoryAdjustmentRecordListEnvelope.fromJson(Map<String,dynamic> json) => InventoryAdjustmentRecordListEnvelope(
    data: (json['data'] as List).map((value) => InventoryAdjustmentRecord.fromJson(Map<String,dynamic>.from(value as Map))).toList(),
    page: Page.fromJson(Map<String,dynamic>.from(json['page'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.map((value) => value.toJson()).toList(),
    'page': page.toJson(),
    'meta': meta.toJson(),
  };
}

class OfferBatchResultEnvelope {
  final OfferBatchResult data;
  final Meta meta;
  const OfferBatchResultEnvelope({required this.data, required this.meta});
  factory OfferBatchResultEnvelope.fromJson(Map<String,dynamic> json) => OfferBatchResultEnvelope(
    data: OfferBatchResult.fromJson(Map<String,dynamic>.from(json['data'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.toJson(),
    'meta': meta.toJson(),
  };
}

class InventoryAdjustmentResultEnvelope {
  final InventoryAdjustmentResult data;
  final Meta meta;
  const InventoryAdjustmentResultEnvelope({required this.data, required this.meta});
  factory InventoryAdjustmentResultEnvelope.fromJson(Map<String,dynamic> json) => InventoryAdjustmentResultEnvelope(
    data: InventoryAdjustmentResult.fromJson(Map<String,dynamic>.from(json['data'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.toJson(),
    'meta': meta.toJson(),
  };
}

class PublicAllergen {
  final String id;
  final String name;
  const PublicAllergen({required this.id, required this.name});
  factory PublicAllergen.fromJson(Map<String,dynamic> json) => PublicAllergen(
    id: json['id'] as String,
    name: json['name'] as String,
  );
  Map<String,dynamic> toJson() => {
    'id': id,
    'name': name,
  };
}

class ConsumerOffer {
  final String offer_id;
  final String merchant_id;
  final String merchant_name;
  final String? store_id;
  final int sale_price_fen;
  final int? member_price_fen;
  final String fulfillment_sla;
  final int offer_version;
  final int available_qty;
  final int inventory_version;
  final bool in_stock;
  const ConsumerOffer({required this.offer_id, required this.merchant_id, required this.merchant_name, required this.store_id, required this.sale_price_fen, required this.member_price_fen, required this.fulfillment_sla, required this.offer_version, required this.available_qty, required this.inventory_version, required this.in_stock});
  factory ConsumerOffer.fromJson(Map<String,dynamic> json) => ConsumerOffer(
    offer_id: json['offer_id'] as String,
    merchant_id: json['merchant_id'] as String,
    merchant_name: json['merchant_name'] as String,
    store_id: json['store_id'] == null ? null : json['store_id'] as String,
    sale_price_fen: (json['sale_price_fen'] as num).toInt(),
    member_price_fen: json['member_price_fen'] == null ? null : (json['member_price_fen'] as num).toInt(),
    fulfillment_sla: json['fulfillment_sla'] as String,
    offer_version: (json['offer_version'] as num).toInt(),
    available_qty: (json['available_qty'] as num).toInt(),
    inventory_version: (json['inventory_version'] as num).toInt(),
    in_stock: json['in_stock'] as bool,
  );
  Map<String,dynamic> toJson() => {
    'offer_id': offer_id,
    'merchant_id': merchant_id,
    'merchant_name': merchant_name,
    'store_id': store_id == null ? null : store_id!,
    'sale_price_fen': sale_price_fen,
    'member_price_fen': member_price_fen == null ? null : member_price_fen!,
    'fulfillment_sla': fulfillment_sla,
    'offer_version': offer_version,
    'available_qty': available_qty,
    'inventory_version': inventory_version,
    'in_stock': in_stock,
  };
}

class ConsumerStandard {
  final String id;
  final String spu_id;
  final String sku_code;
  final int weight_g;
  final String package_unit;
  final String name;
  final String pet_category;
  final String category;
  final String brand;
  final String catalog_standard_version_id;
  final List<String> ingredients;
  final List<CatalogNutrient> nutrients;
  final bool allergens_known;
  final List<String> life_stage_ids;
  final List<String> source_refs;
  final String source_updated_on;
  final String published_at;
  final List<PublicAllergen> allergens;
  const ConsumerStandard({required this.id, required this.spu_id, required this.sku_code, required this.weight_g, required this.package_unit, required this.name, required this.pet_category, required this.category, required this.brand, required this.catalog_standard_version_id, required this.ingredients, required this.nutrients, required this.allergens_known, required this.life_stage_ids, required this.source_refs, required this.source_updated_on, required this.published_at, required this.allergens});
  factory ConsumerStandard.fromJson(Map<String,dynamic> json) => ConsumerStandard(
    id: json['id'] as String,
    spu_id: json['spu_id'] as String,
    sku_code: json['sku_code'] as String,
    weight_g: (json['weight_g'] as num).toInt(),
    package_unit: json['package_unit'] as String,
    name: json['name'] as String,
    pet_category: json['pet_category'] as String,
    category: json['category'] as String,
    brand: json['brand'] as String,
    catalog_standard_version_id: json['catalog_standard_version_id'] as String,
    ingredients: (json['ingredients'] as List).map((value) => value as String).toList(),
    nutrients: (json['nutrients'] as List).map((value) => CatalogNutrient.fromJson(Map<String,dynamic>.from(value as Map))).toList(),
    allergens_known: json['allergens_known'] as bool,
    life_stage_ids: (json['life_stage_ids'] as List).map((value) => value as String).toList(),
    source_refs: (json['source_refs'] as List).map((value) => value as String).toList(),
    source_updated_on: json['source_updated_on'] as String,
    published_at: json['published_at'] as String,
    allergens: (json['allergens'] as List).map((value) => PublicAllergen.fromJson(Map<String,dynamic>.from(value as Map))).toList(),
  );
  Map<String,dynamic> toJson() => {
    'id': id,
    'spu_id': spu_id,
    'sku_code': sku_code,
    'weight_g': weight_g,
    'package_unit': package_unit,
    'name': name,
    'pet_category': pet_category,
    'category': category,
    'brand': brand,
    'catalog_standard_version_id': catalog_standard_version_id,
    'ingredients': ingredients.map((value) => value).toList(),
    'nutrients': nutrients.map((value) => value.toJson()).toList(),
    'allergens_known': allergens_known,
    'life_stage_ids': life_stage_ids.map((value) => value).toList(),
    'source_refs': source_refs.map((value) => value).toList(),
    'source_updated_on': source_updated_on,
    'published_at': published_at,
    'allergens': allergens.map((value) => value.toJson()).toList(),
  };
}

class ConsumerProduct {
  final String id;
  final String spu_id;
  final String sku_code;
  final int weight_g;
  final String package_unit;
  final String name;
  final String pet_category;
  final String category;
  final String brand;
  final String catalog_standard_version_id;
  final List<String> ingredients;
  final List<CatalogNutrient> nutrients;
  final bool allergens_known;
  final List<String> life_stage_ids;
  final List<String> source_refs;
  final String source_updated_on;
  final String published_at;
  final List<PublicAllergen> allergens;
  final List<ConsumerOffer> offers;
  const ConsumerProduct({required this.id, required this.spu_id, required this.sku_code, required this.weight_g, required this.package_unit, required this.name, required this.pet_category, required this.category, required this.brand, required this.catalog_standard_version_id, required this.ingredients, required this.nutrients, required this.allergens_known, required this.life_stage_ids, required this.source_refs, required this.source_updated_on, required this.published_at, required this.allergens, required this.offers});
  factory ConsumerProduct.fromJson(Map<String,dynamic> json) => ConsumerProduct(
    id: json['id'] as String,
    spu_id: json['spu_id'] as String,
    sku_code: json['sku_code'] as String,
    weight_g: (json['weight_g'] as num).toInt(),
    package_unit: json['package_unit'] as String,
    name: json['name'] as String,
    pet_category: json['pet_category'] as String,
    category: json['category'] as String,
    brand: json['brand'] as String,
    catalog_standard_version_id: json['catalog_standard_version_id'] as String,
    ingredients: (json['ingredients'] as List).map((value) => value as String).toList(),
    nutrients: (json['nutrients'] as List).map((value) => CatalogNutrient.fromJson(Map<String,dynamic>.from(value as Map))).toList(),
    allergens_known: json['allergens_known'] as bool,
    life_stage_ids: (json['life_stage_ids'] as List).map((value) => value as String).toList(),
    source_refs: (json['source_refs'] as List).map((value) => value as String).toList(),
    source_updated_on: json['source_updated_on'] as String,
    published_at: json['published_at'] as String,
    allergens: (json['allergens'] as List).map((value) => PublicAllergen.fromJson(Map<String,dynamic>.from(value as Map))).toList(),
    offers: (json['offers'] as List).map((value) => ConsumerOffer.fromJson(Map<String,dynamic>.from(value as Map))).toList(),
  );
  Map<String,dynamic> toJson() => {
    'id': id,
    'spu_id': spu_id,
    'sku_code': sku_code,
    'weight_g': weight_g,
    'package_unit': package_unit,
    'name': name,
    'pet_category': pet_category,
    'category': category,
    'brand': brand,
    'catalog_standard_version_id': catalog_standard_version_id,
    'ingredients': ingredients.map((value) => value).toList(),
    'nutrients': nutrients.map((value) => value.toJson()).toList(),
    'allergens_known': allergens_known,
    'life_stage_ids': life_stage_ids.map((value) => value).toList(),
    'source_refs': source_refs.map((value) => value).toList(),
    'source_updated_on': source_updated_on,
    'published_at': published_at,
    'allergens': allergens.map((value) => value.toJson()).toList(),
    'offers': offers.map((value) => value.toJson()).toList(),
  };
}

class ConsumerSpu {
  final String spu_id;
  final List<ConsumerStandard> skus;
  const ConsumerSpu({required this.spu_id, required this.skus});
  factory ConsumerSpu.fromJson(Map<String,dynamic> json) => ConsumerSpu(
    spu_id: json['spu_id'] as String,
    skus: (json['skus'] as List).map((value) => ConsumerStandard.fromJson(Map<String,dynamic>.from(value as Map))).toList(),
  );
  Map<String,dynamic> toJson() => {
    'spu_id': spu_id,
    'skus': skus.map((value) => value.toJson()).toList(),
  };
}

class FitConflict {
  final String type;
  final String? allergen_id;
  final String message;
  const FitConflict({required this.type, this.allergen_id, required this.message});
  factory FitConflict.fromJson(Map<String,dynamic> json) => FitConflict(
    type: json['type'] as String,
    allergen_id: json['allergen_id'] == null ? null : json['allergen_id'] as String,
    message: json['message'] as String,
  );
  Map<String,dynamic> toJson() => {
    'type': type,
    if (allergen_id != null) 'allergen_id': allergen_id == null ? null : allergen_id!,
    'message': message,
  };
}

class ProductFit {
  final String sku_id;
  final String pet_id;
  final int pet_version;
  final String result;
  final String display_label;
  final List<FitConflict> hard_conflicts;
  final List<String> uncertainties;
  final String catalog_standard_version_id;
  final String fit_rule_version;
  final String? life_stage_id;
  const ProductFit({required this.sku_id, required this.pet_id, required this.pet_version, required this.result, required this.display_label, required this.hard_conflicts, required this.uncertainties, required this.catalog_standard_version_id, required this.fit_rule_version, required this.life_stage_id});
  factory ProductFit.fromJson(Map<String,dynamic> json) => ProductFit(
    sku_id: json['sku_id'] as String,
    pet_id: json['pet_id'] as String,
    pet_version: (json['pet_version'] as num).toInt(),
    result: json['result'] as String,
    display_label: json['display_label'] as String,
    hard_conflicts: (json['hard_conflicts'] as List).map((value) => FitConflict.fromJson(Map<String,dynamic>.from(value as Map))).toList(),
    uncertainties: (json['uncertainties'] as List).map((value) => value as String).toList(),
    catalog_standard_version_id: json['catalog_standard_version_id'] as String,
    fit_rule_version: json['fit_rule_version'] as String,
    life_stage_id: json['life_stage_id'] == null ? null : json['life_stage_id'] as String,
  );
  Map<String,dynamic> toJson() => {
    'sku_id': sku_id,
    'pet_id': pet_id,
    'pet_version': pet_version,
    'result': result,
    'display_label': display_label,
    'hard_conflicts': hard_conflicts.map((value) => value.toJson()).toList(),
    'uncertainties': uncertainties.map((value) => value).toList(),
    'catalog_standard_version_id': catalog_standard_version_id,
    'fit_rule_version': fit_rule_version,
    'life_stage_id': life_stage_id == null ? null : life_stage_id!,
  };
}

class CompareInput {
  final List<String> sku_ids;
  final String? pet_id;
  const CompareInput({required this.sku_ids, this.pet_id});
  factory CompareInput.fromJson(Map<String,dynamic> json) => CompareInput(
    sku_ids: (json['sku_ids'] as List).map((value) => value as String).toList(),
    pet_id: json['pet_id'] == null ? null : json['pet_id'] as String,
  );
  Map<String,dynamic> toJson() => {
    'sku_ids': sku_ids.map((value) => value).toList(),
    if (pet_id != null) 'pet_id': pet_id == null ? null : pet_id!,
  };
}

class CompareItem {
  final ConsumerStandard standard;
  final List<ConsumerOffer> offers;
  final ProductFit? fit;
  const CompareItem({required this.standard, required this.offers, required this.fit});
  factory CompareItem.fromJson(Map<String,dynamic> json) => CompareItem(
    standard: ConsumerStandard.fromJson(Map<String,dynamic>.from(json['standard'] as Map)),
    offers: (json['offers'] as List).map((value) => ConsumerOffer.fromJson(Map<String,dynamic>.from(value as Map))).toList(),
    fit: json['fit'] == null ? null : ProductFit.fromJson(Map<String,dynamic>.from(json['fit'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'standard': standard.toJson(),
    'offers': offers.map((value) => value.toJson()).toList(),
    'fit': fit == null ? null : fit!.toJson(),
  };
}

class ProductComparison {
  final List<CompareItem> items;
  const ProductComparison({required this.items});
  factory ProductComparison.fromJson(Map<String,dynamic> json) => ProductComparison(
    items: (json['items'] as List).map((value) => CompareItem.fromJson(Map<String,dynamic>.from(value as Map))).toList(),
  );
  Map<String,dynamic> toJson() => {
    'items': items.map((value) => value.toJson()).toList(),
  };
}

class ConsumerSpuEnvelope {
  final ConsumerSpu data;
  final Meta meta;
  const ConsumerSpuEnvelope({required this.data, required this.meta});
  factory ConsumerSpuEnvelope.fromJson(Map<String,dynamic> json) => ConsumerSpuEnvelope(
    data: ConsumerSpu.fromJson(Map<String,dynamic>.from(json['data'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.toJson(),
    'meta': meta.toJson(),
  };
}

class ConsumerStandardEnvelope {
  final ConsumerStandard data;
  final Meta meta;
  const ConsumerStandardEnvelope({required this.data, required this.meta});
  factory ConsumerStandardEnvelope.fromJson(Map<String,dynamic> json) => ConsumerStandardEnvelope(
    data: ConsumerStandard.fromJson(Map<String,dynamic>.from(json['data'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.toJson(),
    'meta': meta.toJson(),
  };
}

class ConsumerOfferListEnvelope {
  final List<ConsumerOffer> data;
  final Page page;
  final Meta meta;
  const ConsumerOfferListEnvelope({required this.data, required this.page, required this.meta});
  factory ConsumerOfferListEnvelope.fromJson(Map<String,dynamic> json) => ConsumerOfferListEnvelope(
    data: (json['data'] as List).map((value) => ConsumerOffer.fromJson(Map<String,dynamic>.from(value as Map))).toList(),
    page: Page.fromJson(Map<String,dynamic>.from(json['page'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.map((value) => value.toJson()).toList(),
    'page': page.toJson(),
    'meta': meta.toJson(),
  };
}

class ConsumerProductListEnvelope {
  final List<ConsumerProduct> data;
  final Page page;
  final Meta meta;
  const ConsumerProductListEnvelope({required this.data, required this.page, required this.meta});
  factory ConsumerProductListEnvelope.fromJson(Map<String,dynamic> json) => ConsumerProductListEnvelope(
    data: (json['data'] as List).map((value) => ConsumerProduct.fromJson(Map<String,dynamic>.from(value as Map))).toList(),
    page: Page.fromJson(Map<String,dynamic>.from(json['page'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.map((value) => value.toJson()).toList(),
    'page': page.toJson(),
    'meta': meta.toJson(),
  };
}

class ProductFitEnvelope {
  final ProductFit data;
  final Meta meta;
  const ProductFitEnvelope({required this.data, required this.meta});
  factory ProductFitEnvelope.fromJson(Map<String,dynamic> json) => ProductFitEnvelope(
    data: ProductFit.fromJson(Map<String,dynamic>.from(json['data'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.toJson(),
    'meta': meta.toJson(),
  };
}

class ProductComparisonEnvelope {
  final ProductComparison data;
  final Meta meta;
  const ProductComparisonEnvelope({required this.data, required this.meta});
  factory ProductComparisonEnvelope.fromJson(Map<String,dynamic> json) => ProductComparisonEnvelope(
    data: ProductComparison.fromJson(Map<String,dynamic>.from(json['data'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.toJson(),
    'meta': meta.toJson(),
  };
}

class CheckoutAddressInput {
  final String recipient;
  final String phone;
  final String province_code;
  final String? city_code;
  final String? district_code;
  final String detail;
  const CheckoutAddressInput({required this.recipient, required this.phone, required this.province_code, this.city_code, this.district_code, required this.detail});
  factory CheckoutAddressInput.fromJson(Map<String,dynamic> json) => CheckoutAddressInput(
    recipient: json['recipient'] as String,
    phone: json['phone'] as String,
    province_code: json['province_code'] as String,
    city_code: json['city_code'] == null ? null : json['city_code'] as String,
    district_code: json['district_code'] == null ? null : json['district_code'] as String,
    detail: json['detail'] as String,
  );
  Map<String,dynamic> toJson() => {
    'recipient': recipient,
    'phone': phone,
    'province_code': province_code,
    if (city_code != null) 'city_code': city_code == null ? null : city_code!,
    if (district_code != null) 'district_code': district_code == null ? null : district_code!,
    'detail': detail,
  };
}

class CheckoutAddress {
  final String id;
  final String recipient;
  final String phone;
  final String province_code;
  final String? city_code;
  final String? district_code;
  final String detail;
  final String status;
  final int version;
  final String created_at;
  const CheckoutAddress({required this.id, required this.recipient, required this.phone, required this.province_code, required this.city_code, required this.district_code, required this.detail, required this.status, required this.version, required this.created_at});
  factory CheckoutAddress.fromJson(Map<String,dynamic> json) => CheckoutAddress(
    id: json['id'] as String,
    recipient: json['recipient'] as String,
    phone: json['phone'] as String,
    province_code: json['province_code'] as String,
    city_code: json['city_code'] == null ? null : json['city_code'] as String,
    district_code: json['district_code'] == null ? null : json['district_code'] as String,
    detail: json['detail'] as String,
    status: json['status'] as String,
    version: (json['version'] as num).toInt(),
    created_at: json['created_at'] as String,
  );
  Map<String,dynamic> toJson() => {
    'id': id,
    'recipient': recipient,
    'phone': phone,
    'province_code': province_code,
    'city_code': city_code == null ? null : city_code!,
    'district_code': district_code == null ? null : district_code!,
    'detail': detail,
    'status': status,
    'version': version,
    'created_at': created_at,
  };
}

class CartAddInput {
  final String offer_id;
  final int quantity;
  final String? pet_id;
  const CartAddInput({required this.offer_id, required this.quantity, this.pet_id});
  factory CartAddInput.fromJson(Map<String,dynamic> json) => CartAddInput(
    offer_id: json['offer_id'] as String,
    quantity: (json['quantity'] as num).toInt(),
    pet_id: json['pet_id'] == null ? null : json['pet_id'] as String,
  );
  Map<String,dynamic> toJson() => {
    'offer_id': offer_id,
    'quantity': quantity,
    if (pet_id != null) 'pet_id': pet_id == null ? null : pet_id!,
  };
}

class CartQuantityInput {
  final int quantity;
  const CartQuantityInput({required this.quantity});
  factory CartQuantityInput.fromJson(Map<String,dynamic> json) => CartQuantityInput(
    quantity: (json['quantity'] as num).toInt(),
  );
  Map<String,dynamic> toJson() => {
    'quantity': quantity,
  };
}

class CartItem {
  final String id;
  final String cart_id;
  final String offer_id;
  final String? pet_id;
  final int quantity;
  final bool active;
  final int version;
  final String created_at;
  final String? availability;
  final String? name;
  final String? merchant_name;
  final int? sale_price_fen;
  final int? available_qty;
  const CartItem({required this.id, required this.cart_id, required this.offer_id, required this.pet_id, required this.quantity, required this.active, required this.version, required this.created_at, this.availability, this.name, this.merchant_name, this.sale_price_fen, this.available_qty});
  factory CartItem.fromJson(Map<String,dynamic> json) => CartItem(
    id: json['id'] as String,
    cart_id: json['cart_id'] as String,
    offer_id: json['offer_id'] as String,
    pet_id: json['pet_id'] == null ? null : json['pet_id'] as String,
    quantity: (json['quantity'] as num).toInt(),
    active: json['active'] as bool,
    version: (json['version'] as num).toInt(),
    created_at: json['created_at'] as String,
    availability: json['availability'] == null ? null : json['availability'] as String,
    name: json['name'] == null ? null : json['name'] as String,
    merchant_name: json['merchant_name'] == null ? null : json['merchant_name'] as String,
    sale_price_fen: json['sale_price_fen'] == null ? null : (json['sale_price_fen'] as num).toInt(),
    available_qty: json['available_qty'] == null ? null : (json['available_qty'] as num).toInt(),
  );
  Map<String,dynamic> toJson() => {
    'id': id,
    'cart_id': cart_id,
    'offer_id': offer_id,
    'pet_id': pet_id == null ? null : pet_id!,
    'quantity': quantity,
    'active': active,
    'version': version,
    'created_at': created_at,
    if (availability != null) 'availability': availability == null ? null : availability!,
    if (name != null) 'name': name == null ? null : name!,
    if (merchant_name != null) 'merchant_name': merchant_name == null ? null : merchant_name!,
    if (sale_price_fen != null) 'sale_price_fen': sale_price_fen == null ? null : sale_price_fen!,
    if (available_qty != null) 'available_qty': available_qty == null ? null : available_qty!,
  };
}

class Cart {
  final String id;
  final int version;
  final List<CartItem> items;
  const Cart({required this.id, required this.version, required this.items});
  factory Cart.fromJson(Map<String,dynamic> json) => Cart(
    id: json['id'] as String,
    version: (json['version'] as num).toInt(),
    items: (json['items'] as List).map((value) => CartItem.fromJson(Map<String,dynamic>.from(value as Map))).toList(),
  );
  Map<String,dynamic> toJson() => {
    'id': id,
    'version': version,
    'items': items.map((value) => value.toJson()).toList(),
  };
}

class CartMergeInput {
  final List<CartAddInput> items;
  const CartMergeInput({required this.items});
  factory CartMergeInput.fromJson(Map<String,dynamic> json) => CartMergeInput(
    items: (json['items'] as List).map((value) => CartAddInput.fromJson(Map<String,dynamic>.from(value as Map))).toList(),
  );
  Map<String,dynamic> toJson() => {
    'items': items.map((value) => value.toJson()).toList(),
  };
}

class CheckoutDeleted {
  final String id;
  final bool deleted;
  const CheckoutDeleted({required this.id, required this.deleted});
  factory CheckoutDeleted.fromJson(Map<String,dynamic> json) => CheckoutDeleted(
    id: json['id'] as String,
    deleted: json['deleted'] as bool,
  );
  Map<String,dynamic> toJson() => {
    'id': id,
    'deleted': deleted,
  };
}

class ShippingRuleInput {
  final List<String> province_codes;
  final int base_fen;
  final int per_kg_fen;
  final int? free_threshold_fen;
  const ShippingRuleInput({required this.province_codes, required this.base_fen, required this.per_kg_fen, this.free_threshold_fen});
  factory ShippingRuleInput.fromJson(Map<String,dynamic> json) => ShippingRuleInput(
    province_codes: (json['province_codes'] as List).map((value) => value as String).toList(),
    base_fen: (json['base_fen'] as num).toInt(),
    per_kg_fen: (json['per_kg_fen'] as num).toInt(),
    free_threshold_fen: json['free_threshold_fen'] == null ? null : (json['free_threshold_fen'] as num).toInt(),
  );
  Map<String,dynamic> toJson() => {
    'province_codes': province_codes.map((value) => value).toList(),
    'base_fen': base_fen,
    'per_kg_fen': per_kg_fen,
    if (free_threshold_fen != null) 'free_threshold_fen': free_threshold_fen == null ? null : free_threshold_fen!,
  };
}

class ShippingRule {
  final String id;
  final String merchant_id;
  final int version_no;
  final List<String> province_codes;
  final int base_fen;
  final int per_kg_fen;
  final int? free_threshold_fen;
  final String created_at;
  const ShippingRule({required this.id, required this.merchant_id, required this.version_no, required this.province_codes, required this.base_fen, required this.per_kg_fen, required this.free_threshold_fen, required this.created_at});
  factory ShippingRule.fromJson(Map<String,dynamic> json) => ShippingRule(
    id: json['id'] as String,
    merchant_id: json['merchant_id'] as String,
    version_no: (json['version_no'] as num).toInt(),
    province_codes: (json['province_codes'] as List).map((value) => value as String).toList(),
    base_fen: (json['base_fen'] as num).toInt(),
    per_kg_fen: (json['per_kg_fen'] as num).toInt(),
    free_threshold_fen: json['free_threshold_fen'] == null ? null : (json['free_threshold_fen'] as num).toInt(),
    created_at: json['created_at'] as String,
  );
  Map<String,dynamic> toJson() => {
    'id': id,
    'merchant_id': merchant_id,
    'version_no': version_no,
    'province_codes': province_codes.map((value) => value).toList(),
    'base_fen': base_fen,
    'per_kg_fen': per_kg_fen,
    'free_threshold_fen': free_threshold_fen == null ? null : free_threshold_fen!,
    'created_at': created_at,
  };
}

class QuoteInput {
  final List<String> cart_item_ids;
  final String address_id;
  final List<String>? coupon_ids;
  final bool? use_membership;
  const QuoteInput({required this.cart_item_ids, required this.address_id, this.coupon_ids, this.use_membership});
  factory QuoteInput.fromJson(Map<String,dynamic> json) => QuoteInput(
    cart_item_ids: (json['cart_item_ids'] as List).map((value) => value as String).toList(),
    address_id: json['address_id'] as String,
    coupon_ids: json['coupon_ids'] == null ? null : (json['coupon_ids'] as List).map((value) => value as String).toList(),
    use_membership: json['use_membership'] == null ? null : json['use_membership'] as bool,
  );
  Map<String,dynamic> toJson() => {
    'cart_item_ids': cart_item_ids.map((value) => value).toList(),
    'address_id': address_id,
    if (coupon_ids != null) 'coupon_ids': coupon_ids == null ? null : coupon_ids!.map((value) => value).toList(),
    if (use_membership != null) 'use_membership': use_membership == null ? null : use_membership!,
  };
}

class QuoteMembership {
  final bool used;
  final String? plan_version_id;
  final String? starts_at;
  final String? expires_at;
  final String? status;
  final int? version;
  const QuoteMembership({required this.used, this.plan_version_id, this.starts_at, this.expires_at, this.status, this.version});
  factory QuoteMembership.fromJson(Map<String,dynamic> json) => QuoteMembership(
    used: json['used'] as bool,
    plan_version_id: json['plan_version_id'] == null ? null : json['plan_version_id'] as String,
    starts_at: json['starts_at'] == null ? null : json['starts_at'] as String,
    expires_at: json['expires_at'] == null ? null : json['expires_at'] as String,
    status: json['status'] == null ? null : json['status'] as String,
    version: json['version'] == null ? null : (json['version'] as num).toInt(),
  );
  Map<String,dynamic> toJson() => {
    'used': used,
    if (plan_version_id != null) 'plan_version_id': plan_version_id == null ? null : plan_version_id!,
    if (starts_at != null) 'starts_at': starts_at == null ? null : starts_at!,
    if (expires_at != null) 'expires_at': expires_at == null ? null : expires_at!,
    if (status != null) 'status': status == null ? null : status!,
    if (version != null) 'version': version == null ? null : version!,
  };
}

class QuoteItem {
  final String sku_id;
  final String merchant_id;
  final String cart_item_id;
  final int cart_item_version;
  final String offer_id;
  final int offer_version;
  final String catalog_standard_version_id;
  final int quantity;
  final int unit_price_fen;
  final int goods_amount_fen;
  final String allocation_key;
  final String name;
  final String merchant_name;
  final int payable_amount_fen;
  final int discount_amount_fen;
  const QuoteItem({required this.sku_id, required this.merchant_id, required this.cart_item_id, required this.cart_item_version, required this.offer_id, required this.offer_version, required this.catalog_standard_version_id, required this.quantity, required this.unit_price_fen, required this.goods_amount_fen, required this.allocation_key, required this.name, required this.merchant_name, required this.payable_amount_fen, required this.discount_amount_fen});
  factory QuoteItem.fromJson(Map<String,dynamic> json) => QuoteItem(
    sku_id: json['sku_id'] as String,
    merchant_id: json['merchant_id'] as String,
    cart_item_id: json['cart_item_id'] as String,
    cart_item_version: (json['cart_item_version'] as num).toInt(),
    offer_id: json['offer_id'] as String,
    offer_version: (json['offer_version'] as num).toInt(),
    catalog_standard_version_id: json['catalog_standard_version_id'] as String,
    quantity: (json['quantity'] as num).toInt(),
    unit_price_fen: (json['unit_price_fen'] as num).toInt(),
    goods_amount_fen: (json['goods_amount_fen'] as num).toInt(),
    allocation_key: json['allocation_key'] as String,
    name: json['name'] as String,
    merchant_name: json['merchant_name'] as String,
    payable_amount_fen: (json['payable_amount_fen'] as num).toInt(),
    discount_amount_fen: (json['discount_amount_fen'] as num).toInt(),
  );
  Map<String,dynamic> toJson() => {
    'sku_id': sku_id,
    'merchant_id': merchant_id,
    'cart_item_id': cart_item_id,
    'cart_item_version': cart_item_version,
    'offer_id': offer_id,
    'offer_version': offer_version,
    'catalog_standard_version_id': catalog_standard_version_id,
    'quantity': quantity,
    'unit_price_fen': unit_price_fen,
    'goods_amount_fen': goods_amount_fen,
    'allocation_key': allocation_key,
    'name': name,
    'merchant_name': merchant_name,
    'payable_amount_fen': payable_amount_fen,
    'discount_amount_fen': discount_amount_fen,
  };
}

class QuoteMerchantGroup {
  final String merchant_id;
  final String merchant_name;
  final int goods_amount_fen;
  final int goods_discount_fen;
  final int goods_payable_fen;
  final String shipping_rule_id;
  final int shipping_amount_fen;
  final int shipping_payable_fen;
  final int shipping_discount_fen;
  const QuoteMerchantGroup({required this.merchant_id, required this.merchant_name, required this.goods_amount_fen, required this.goods_discount_fen, required this.goods_payable_fen, required this.shipping_rule_id, required this.shipping_amount_fen, required this.shipping_payable_fen, required this.shipping_discount_fen});
  factory QuoteMerchantGroup.fromJson(Map<String,dynamic> json) => QuoteMerchantGroup(
    merchant_id: json['merchant_id'] as String,
    merchant_name: json['merchant_name'] as String,
    goods_amount_fen: (json['goods_amount_fen'] as num).toInt(),
    goods_discount_fen: (json['goods_discount_fen'] as num).toInt(),
    goods_payable_fen: (json['goods_payable_fen'] as num).toInt(),
    shipping_rule_id: json['shipping_rule_id'] as String,
    shipping_amount_fen: (json['shipping_amount_fen'] as num).toInt(),
    shipping_payable_fen: (json['shipping_payable_fen'] as num).toInt(),
    shipping_discount_fen: (json['shipping_discount_fen'] as num).toInt(),
  );
  Map<String,dynamic> toJson() => {
    'merchant_id': merchant_id,
    'merchant_name': merchant_name,
    'goods_amount_fen': goods_amount_fen,
    'goods_discount_fen': goods_discount_fen,
    'goods_payable_fen': goods_payable_fen,
    'shipping_rule_id': shipping_rule_id,
    'shipping_amount_fen': shipping_amount_fen,
    'shipping_payable_fen': shipping_payable_fen,
    'shipping_discount_fen': shipping_discount_fen,
  };
}

class CheckoutCoupon {
  final String id;
  final String scope;
  final String? merchant_id;
  final String? merchant_name;
  final int amount_fen;
  final int threshold_fen;
  final String expires_at;
  final int version;
  const CheckoutCoupon({required this.id, required this.scope, required this.merchant_id, required this.merchant_name, required this.amount_fen, required this.threshold_fen, required this.expires_at, required this.version});
  factory CheckoutCoupon.fromJson(Map<String,dynamic> json) => CheckoutCoupon(
    id: json['id'] as String,
    scope: json['scope'] as String,
    merchant_id: json['merchant_id'] == null ? null : json['merchant_id'] as String,
    merchant_name: json['merchant_name'] == null ? null : json['merchant_name'] as String,
    amount_fen: (json['amount_fen'] as num).toInt(),
    threshold_fen: (json['threshold_fen'] as num).toInt(),
    expires_at: json['expires_at'] as String,
    version: (json['version'] as num).toInt(),
  );
  Map<String,dynamic> toJson() => {
    'id': id,
    'scope': scope,
    'merchant_id': merchant_id == null ? null : merchant_id!,
    'merchant_name': merchant_name == null ? null : merchant_name!,
    'amount_fen': amount_fen,
    'threshold_fen': threshold_fen,
    'expires_at': expires_at,
    'version': version,
  };
}

class CheckoutBenefits {
  final bool membership_eligible;
  final List<CheckoutCoupon> coupons;
  const CheckoutBenefits({required this.membership_eligible, required this.coupons});
  factory CheckoutBenefits.fromJson(Map<String,dynamic> json) => CheckoutBenefits(
    membership_eligible: json['membership_eligible'] as bool,
    coupons: (json['coupons'] as List).map((value) => CheckoutCoupon.fromJson(Map<String,dynamic>.from(value as Map))).toList(),
  );
  Map<String,dynamic> toJson() => {
    'membership_eligible': membership_eligible,
    'coupons': coupons.map((value) => value.toJson()).toList(),
  };
}

class QuoteDiscountAllocation {
  final String source_id;
  final int sequence_no;
  final String scope;
  final String allocation_key;
  final int eligible_base_fen;
  final int discount_fen;
  const QuoteDiscountAllocation({required this.source_id, required this.sequence_no, required this.scope, required this.allocation_key, required this.eligible_base_fen, required this.discount_fen});
  factory QuoteDiscountAllocation.fromJson(Map<String,dynamic> json) => QuoteDiscountAllocation(
    source_id: json['source_id'] as String,
    sequence_no: (json['sequence_no'] as num).toInt(),
    scope: json['scope'] as String,
    allocation_key: json['allocation_key'] as String,
    eligible_base_fen: (json['eligible_base_fen'] as num).toInt(),
    discount_fen: (json['discount_fen'] as num).toInt(),
  );
  Map<String,dynamic> toJson() => {
    'source_id': source_id,
    'sequence_no': sequence_no,
    'scope': scope,
    'allocation_key': allocation_key,
    'eligible_base_fen': eligible_base_fen,
    'discount_fen': discount_fen,
  };
}

class PricingQuote {
  final String quote_id;
  final String status;
  final int version;
  final String expires_at;
  final String currency;
  final int goods_amount_fen;
  final int shipping_amount_fen;
  final int discount_amount_fen;
  final int payable_amount_fen;
  final String pricing_rule_version;
  final String algorithm_version;
  final CheckoutAddress address_snapshot;
  final QuoteMembership membership_snapshot;
  final List<QuoteItem> items;
  final List<QuoteMerchantGroup> merchant_groups;
  final List<QuoteDiscountAllocation> discount_allocations;
  const PricingQuote({required this.quote_id, required this.status, required this.version, required this.expires_at, required this.currency, required this.goods_amount_fen, required this.shipping_amount_fen, required this.discount_amount_fen, required this.payable_amount_fen, required this.pricing_rule_version, required this.algorithm_version, required this.address_snapshot, required this.membership_snapshot, required this.items, required this.merchant_groups, required this.discount_allocations});
  factory PricingQuote.fromJson(Map<String,dynamic> json) => PricingQuote(
    quote_id: json['quote_id'] as String,
    status: json['status'] as String,
    version: (json['version'] as num).toInt(),
    expires_at: json['expires_at'] as String,
    currency: json['currency'] as String,
    goods_amount_fen: (json['goods_amount_fen'] as num).toInt(),
    shipping_amount_fen: (json['shipping_amount_fen'] as num).toInt(),
    discount_amount_fen: (json['discount_amount_fen'] as num).toInt(),
    payable_amount_fen: (json['payable_amount_fen'] as num).toInt(),
    pricing_rule_version: json['pricing_rule_version'] as String,
    algorithm_version: json['algorithm_version'] as String,
    address_snapshot: CheckoutAddress.fromJson(Map<String,dynamic>.from(json['address_snapshot'] as Map)),
    membership_snapshot: QuoteMembership.fromJson(Map<String,dynamic>.from(json['membership_snapshot'] as Map)),
    items: (json['items'] as List).map((value) => QuoteItem.fromJson(Map<String,dynamic>.from(value as Map))).toList(),
    merchant_groups: (json['merchant_groups'] as List).map((value) => QuoteMerchantGroup.fromJson(Map<String,dynamic>.from(value as Map))).toList(),
    discount_allocations: (json['discount_allocations'] as List).map((value) => QuoteDiscountAllocation.fromJson(Map<String,dynamic>.from(value as Map))).toList(),
  );
  Map<String,dynamic> toJson() => {
    'quote_id': quote_id,
    'status': status,
    'version': version,
    'expires_at': expires_at,
    'currency': currency,
    'goods_amount_fen': goods_amount_fen,
    'shipping_amount_fen': shipping_amount_fen,
    'discount_amount_fen': discount_amount_fen,
    'payable_amount_fen': payable_amount_fen,
    'pricing_rule_version': pricing_rule_version,
    'algorithm_version': algorithm_version,
    'address_snapshot': address_snapshot.toJson(),
    'membership_snapshot': membership_snapshot.toJson(),
    'items': items.map((value) => value.toJson()).toList(),
    'merchant_groups': merchant_groups.map((value) => value.toJson()).toList(),
    'discount_allocations': discount_allocations.map((value) => value.toJson()).toList(),
  };
}

class CartEnvelope {
  final Cart data;
  final Meta meta;
  const CartEnvelope({required this.data, required this.meta});
  factory CartEnvelope.fromJson(Map<String,dynamic> json) => CartEnvelope(
    data: Cart.fromJson(Map<String,dynamic>.from(json['data'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.toJson(),
    'meta': meta.toJson(),
  };
}

class CheckoutBenefitsEnvelope {
  final CheckoutBenefits data;
  final Meta meta;
  const CheckoutBenefitsEnvelope({required this.data, required this.meta});
  factory CheckoutBenefitsEnvelope.fromJson(Map<String,dynamic> json) => CheckoutBenefitsEnvelope(
    data: CheckoutBenefits.fromJson(Map<String,dynamic>.from(json['data'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.toJson(),
    'meta': meta.toJson(),
  };
}

class CartItemEnvelope {
  final CartItem data;
  final Meta meta;
  const CartItemEnvelope({required this.data, required this.meta});
  factory CartItemEnvelope.fromJson(Map<String,dynamic> json) => CartItemEnvelope(
    data: CartItem.fromJson(Map<String,dynamic>.from(json['data'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.toJson(),
    'meta': meta.toJson(),
  };
}

class CheckoutDeletedEnvelope {
  final CheckoutDeleted data;
  final Meta meta;
  const CheckoutDeletedEnvelope({required this.data, required this.meta});
  factory CheckoutDeletedEnvelope.fromJson(Map<String,dynamic> json) => CheckoutDeletedEnvelope(
    data: CheckoutDeleted.fromJson(Map<String,dynamic>.from(json['data'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.toJson(),
    'meta': meta.toJson(),
  };
}

class CheckoutAddressListEnvelope {
  final List<CheckoutAddress> data;
  final Page page;
  final Meta meta;
  const CheckoutAddressListEnvelope({required this.data, required this.page, required this.meta});
  factory CheckoutAddressListEnvelope.fromJson(Map<String,dynamic> json) => CheckoutAddressListEnvelope(
    data: (json['data'] as List).map((value) => CheckoutAddress.fromJson(Map<String,dynamic>.from(value as Map))).toList(),
    page: Page.fromJson(Map<String,dynamic>.from(json['page'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.map((value) => value.toJson()).toList(),
    'page': page.toJson(),
    'meta': meta.toJson(),
  };
}

class CheckoutAddressEnvelope {
  final CheckoutAddress data;
  final Meta meta;
  const CheckoutAddressEnvelope({required this.data, required this.meta});
  factory CheckoutAddressEnvelope.fromJson(Map<String,dynamic> json) => CheckoutAddressEnvelope(
    data: CheckoutAddress.fromJson(Map<String,dynamic>.from(json['data'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.toJson(),
    'meta': meta.toJson(),
  };
}

class PricingQuoteEnvelope {
  final PricingQuote data;
  final Meta meta;
  const PricingQuoteEnvelope({required this.data, required this.meta});
  factory PricingQuoteEnvelope.fromJson(Map<String,dynamic> json) => PricingQuoteEnvelope(
    data: PricingQuote.fromJson(Map<String,dynamic>.from(json['data'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.toJson(),
    'meta': meta.toJson(),
  };
}

class ShippingRuleEnvelope {
  final ShippingRule data;
  final Meta meta;
  const ShippingRuleEnvelope({required this.data, required this.meta});
  factory ShippingRuleEnvelope.fromJson(Map<String,dynamic> json) => ShippingRuleEnvelope(
    data: ShippingRule.fromJson(Map<String,dynamic>.from(json['data'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.toJson(),
    'meta': meta.toJson(),
  };
}

class OrderInput {
  final String quote_id;
  const OrderInput({required this.quote_id});
  factory OrderInput.fromJson(Map<String,dynamic> json) => OrderInput(
    quote_id: json['quote_id'] as String,
  );
  Map<String,dynamic> toJson() => {
    'quote_id': quote_id,
  };
}

class OrderCancelInput {
  final String reason_code;
  const OrderCancelInput({required this.reason_code});
  factory OrderCancelInput.fromJson(Map<String,dynamic> json) => OrderCancelInput(
    reason_code: json['reason_code'] as String,
  );
  Map<String,dynamic> toJson() => {
    'reason_code': reason_code,
  };
}

class OrderPolicyInput {
  final String version_code;
  final int reservation_ttl_seconds;
  const OrderPolicyInput({required this.version_code, required this.reservation_ttl_seconds});
  factory OrderPolicyInput.fromJson(Map<String,dynamic> json) => OrderPolicyInput(
    version_code: json['version_code'] as String,
    reservation_ttl_seconds: (json['reservation_ttl_seconds'] as num).toInt(),
  );
  Map<String,dynamic> toJson() => {
    'version_code': version_code,
    'reservation_ttl_seconds': reservation_ttl_seconds,
  };
}

class OrderPolicy {
  final String id;
  final int version_no;
  final String version_code;
  final int reservation_ttl_seconds;
  final String created_at;
  const OrderPolicy({required this.id, required this.version_no, required this.version_code, required this.reservation_ttl_seconds, required this.created_at});
  factory OrderPolicy.fromJson(Map<String,dynamic> json) => OrderPolicy(
    id: json['id'] as String,
    version_no: (json['version_no'] as num).toInt(),
    version_code: json['version_code'] as String,
    reservation_ttl_seconds: (json['reservation_ttl_seconds'] as num).toInt(),
    created_at: json['created_at'] as String,
  );
  Map<String,dynamic> toJson() => {
    'id': id,
    'version_no': version_no,
    'version_code': version_code,
    'reservation_ttl_seconds': reservation_ttl_seconds,
    'created_at': created_at,
  };
}

class OrderSummary {
  final String id;
  final String order_no;
  final String quote_id;
  final String currency;
  final int goods_amount_fen;
  final int shipping_amount_fen;
  final int discount_amount_fen;
  final int payable_amount_fen;
  final String policy_version_id;
  final String reservation_expires_at;
  final String status;
  final int version;
  final String created_at;
  const OrderSummary({required this.id, required this.order_no, required this.quote_id, required this.currency, required this.goods_amount_fen, required this.shipping_amount_fen, required this.discount_amount_fen, required this.payable_amount_fen, required this.policy_version_id, required this.reservation_expires_at, required this.status, required this.version, required this.created_at});
  factory OrderSummary.fromJson(Map<String,dynamic> json) => OrderSummary(
    id: json['id'] as String,
    order_no: json['order_no'] as String,
    quote_id: json['quote_id'] as String,
    currency: json['currency'] as String,
    goods_amount_fen: (json['goods_amount_fen'] as num).toInt(),
    shipping_amount_fen: (json['shipping_amount_fen'] as num).toInt(),
    discount_amount_fen: (json['discount_amount_fen'] as num).toInt(),
    payable_amount_fen: (json['payable_amount_fen'] as num).toInt(),
    policy_version_id: json['policy_version_id'] as String,
    reservation_expires_at: json['reservation_expires_at'] as String,
    status: json['status'] as String,
    version: (json['version'] as num).toInt(),
    created_at: json['created_at'] as String,
  );
  Map<String,dynamic> toJson() => {
    'id': id,
    'order_no': order_no,
    'quote_id': quote_id,
    'currency': currency,
    'goods_amount_fen': goods_amount_fen,
    'shipping_amount_fen': shipping_amount_fen,
    'discount_amount_fen': discount_amount_fen,
    'payable_amount_fen': payable_amount_fen,
    'policy_version_id': policy_version_id,
    'reservation_expires_at': reservation_expires_at,
    'status': status,
    'version': version,
    'created_at': created_at,
  };
}

class OrderProductSnapshot {
  final String? store_id;
  final String fulfillment_sla;
  final int offer_version;
  final String sku_code;
  final int weight_g;
  final String package_unit;
  final String name;
  final String brand;
  final String standard_version_id;
  final Map<String,dynamic> standard_snapshot;
  final String? pet_id;
  final bool member_price_used;
  const OrderProductSnapshot({required this.store_id, required this.fulfillment_sla, required this.offer_version, required this.sku_code, required this.weight_g, required this.package_unit, required this.name, required this.brand, required this.standard_version_id, required this.standard_snapshot, required this.pet_id, required this.member_price_used});
  factory OrderProductSnapshot.fromJson(Map<String,dynamic> json) => OrderProductSnapshot(
    store_id: json['store_id'] == null ? null : json['store_id'] as String,
    fulfillment_sla: json['fulfillment_sla'] as String,
    offer_version: (json['offer_version'] as num).toInt(),
    sku_code: json['sku_code'] as String,
    weight_g: (json['weight_g'] as num).toInt(),
    package_unit: json['package_unit'] as String,
    name: json['name'] as String,
    brand: json['brand'] as String,
    standard_version_id: json['standard_version_id'] as String,
    standard_snapshot: Map<String,dynamic>.from(json['standard_snapshot'] as Map),
    pet_id: json['pet_id'] == null ? null : json['pet_id'] as String,
    member_price_used: json['member_price_used'] as bool,
  );
  Map<String,dynamic> toJson() => {
    'store_id': store_id == null ? null : store_id!,
    'fulfillment_sla': fulfillment_sla,
    'offer_version': offer_version,
    'sku_code': sku_code,
    'weight_g': weight_g,
    'package_unit': package_unit,
    'name': name,
    'brand': brand,
    'standard_version_id': standard_version_id,
    'standard_snapshot': standard_snapshot,
    'pet_id': pet_id == null ? null : pet_id!,
    'member_price_used': member_price_used,
  };
}

class OrderItem {
  final String id;
  final String suborder_id;
  final String allocation_key;
  final String offer_id;
  final String sku_id;
  final String merchant_id;
  final String? store_id;
  final int quantity;
  final int cancelled_qty;
  final int unit_price_fen;
  final int goods_amount_fen;
  final int discount_amount_fen;
  final int payable_amount_fen;
  final OrderProductSnapshot product_snapshot;
  const OrderItem({required this.id, required this.suborder_id, required this.allocation_key, required this.offer_id, required this.sku_id, required this.merchant_id, required this.store_id, required this.quantity, required this.cancelled_qty, required this.unit_price_fen, required this.goods_amount_fen, required this.discount_amount_fen, required this.payable_amount_fen, required this.product_snapshot});
  factory OrderItem.fromJson(Map<String,dynamic> json) => OrderItem(
    id: json['id'] as String,
    suborder_id: json['suborder_id'] as String,
    allocation_key: json['allocation_key'] as String,
    offer_id: json['offer_id'] as String,
    sku_id: json['sku_id'] as String,
    merchant_id: json['merchant_id'] as String,
    store_id: json['store_id'] == null ? null : json['store_id'] as String,
    quantity: (json['quantity'] as num).toInt(),
    cancelled_qty: (json['cancelled_qty'] as num).toInt(),
    unit_price_fen: (json['unit_price_fen'] as num).toInt(),
    goods_amount_fen: (json['goods_amount_fen'] as num).toInt(),
    discount_amount_fen: (json['discount_amount_fen'] as num).toInt(),
    payable_amount_fen: (json['payable_amount_fen'] as num).toInt(),
    product_snapshot: OrderProductSnapshot.fromJson(Map<String,dynamic>.from(json['product_snapshot'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'id': id,
    'suborder_id': suborder_id,
    'allocation_key': allocation_key,
    'offer_id': offer_id,
    'sku_id': sku_id,
    'merchant_id': merchant_id,
    'store_id': store_id == null ? null : store_id!,
    'quantity': quantity,
    'cancelled_qty': cancelled_qty,
    'unit_price_fen': unit_price_fen,
    'goods_amount_fen': goods_amount_fen,
    'discount_amount_fen': discount_amount_fen,
    'payable_amount_fen': payable_amount_fen,
    'product_snapshot': product_snapshot.toJson(),
  };
}

class Suborder {
  final String id;
  final String order_id;
  final String merchant_id;
  final String suborder_no;
  final String merchant_name;
  final String fulfillment_status;
  final int goods_amount_fen;
  final int shipping_amount_fen;
  final int discount_amount_fen;
  final int payable_amount_fen;
  final QuoteMerchantGroup shipping_snapshot;
  final int version;
  final String created_at;
  final List<OrderItem> items;
  const Suborder({required this.id, required this.order_id, required this.merchant_id, required this.suborder_no, required this.merchant_name, required this.fulfillment_status, required this.goods_amount_fen, required this.shipping_amount_fen, required this.discount_amount_fen, required this.payable_amount_fen, required this.shipping_snapshot, required this.version, required this.created_at, required this.items});
  factory Suborder.fromJson(Map<String,dynamic> json) => Suborder(
    id: json['id'] as String,
    order_id: json['order_id'] as String,
    merchant_id: json['merchant_id'] as String,
    suborder_no: json['suborder_no'] as String,
    merchant_name: json['merchant_name'] as String,
    fulfillment_status: json['fulfillment_status'] as String,
    goods_amount_fen: (json['goods_amount_fen'] as num).toInt(),
    shipping_amount_fen: (json['shipping_amount_fen'] as num).toInt(),
    discount_amount_fen: (json['discount_amount_fen'] as num).toInt(),
    payable_amount_fen: (json['payable_amount_fen'] as num).toInt(),
    shipping_snapshot: QuoteMerchantGroup.fromJson(Map<String,dynamic>.from(json['shipping_snapshot'] as Map)),
    version: (json['version'] as num).toInt(),
    created_at: json['created_at'] as String,
    items: (json['items'] as List).map((value) => OrderItem.fromJson(Map<String,dynamic>.from(value as Map))).toList(),
  );
  Map<String,dynamic> toJson() => {
    'id': id,
    'order_id': order_id,
    'merchant_id': merchant_id,
    'suborder_no': suborder_no,
    'merchant_name': merchant_name,
    'fulfillment_status': fulfillment_status,
    'goods_amount_fen': goods_amount_fen,
    'shipping_amount_fen': shipping_amount_fen,
    'discount_amount_fen': discount_amount_fen,
    'payable_amount_fen': payable_amount_fen,
    'shipping_snapshot': shipping_snapshot.toJson(),
    'version': version,
    'created_at': created_at,
    'items': items.map((value) => value.toJson()).toList(),
  };
}

class PaymentIntent {
  final String id;
  final String payment_no;
  final String order_id;
  final int amount_fen;
  final String currency;
  final String status;
  final String expires_at;
  final int version;
  final String created_at;
  const PaymentIntent({required this.id, required this.payment_no, required this.order_id, required this.amount_fen, required this.currency, required this.status, required this.expires_at, required this.version, required this.created_at});
  factory PaymentIntent.fromJson(Map<String,dynamic> json) => PaymentIntent(
    id: json['id'] as String,
    payment_no: json['payment_no'] as String,
    order_id: json['order_id'] as String,
    amount_fen: (json['amount_fen'] as num).toInt(),
    currency: json['currency'] as String,
    status: json['status'] as String,
    expires_at: json['expires_at'] as String,
    version: (json['version'] as num).toInt(),
    created_at: json['created_at'] as String,
  );
  Map<String,dynamic> toJson() => {
    'id': id,
    'payment_no': payment_no,
    'order_id': order_id,
    'amount_fen': amount_fen,
    'currency': currency,
    'status': status,
    'expires_at': expires_at,
    'version': version,
    'created_at': created_at,
  };
}

class InventoryReservation {
  final String id;
  final String order_id;
  final String offer_id;
  final int quantity;
  final String status;
  final int reservation_generation;
  final String expires_at;
  final int version;
  final String created_at;
  const InventoryReservation({required this.id, required this.order_id, required this.offer_id, required this.quantity, required this.status, required this.reservation_generation, required this.expires_at, required this.version, required this.created_at});
  factory InventoryReservation.fromJson(Map<String,dynamic> json) => InventoryReservation(
    id: json['id'] as String,
    order_id: json['order_id'] as String,
    offer_id: json['offer_id'] as String,
    quantity: (json['quantity'] as num).toInt(),
    status: json['status'] as String,
    reservation_generation: (json['reservation_generation'] as num).toInt(),
    expires_at: json['expires_at'] as String,
    version: (json['version'] as num).toInt(),
    created_at: json['created_at'] as String,
  );
  Map<String,dynamic> toJson() => {
    'id': id,
    'order_id': order_id,
    'offer_id': offer_id,
    'quantity': quantity,
    'status': status,
    'reservation_generation': reservation_generation,
    'expires_at': expires_at,
    'version': version,
    'created_at': created_at,
  };
}

class UnpaidCancellation {
  final String id;
  final String order_id;
  final String actor_type;
  final String? actor_id;
  final String reason_code;
  final String status;
  final String created_at;
  const UnpaidCancellation({required this.id, required this.order_id, required this.actor_type, required this.actor_id, required this.reason_code, required this.status, required this.created_at});
  factory UnpaidCancellation.fromJson(Map<String,dynamic> json) => UnpaidCancellation(
    id: json['id'] as String,
    order_id: json['order_id'] as String,
    actor_type: json['actor_type'] as String,
    actor_id: json['actor_id'] == null ? null : json['actor_id'] as String,
    reason_code: json['reason_code'] as String,
    status: json['status'] as String,
    created_at: json['created_at'] as String,
  );
  Map<String,dynamic> toJson() => {
    'id': id,
    'order_id': order_id,
    'actor_type': actor_type,
    'actor_id': actor_id == null ? null : actor_id!,
    'reason_code': reason_code,
    'status': status,
    'created_at': created_at,
  };
}

class Order {
  final String id;
  final String order_no;
  final String quote_id;
  final String currency;
  final int goods_amount_fen;
  final int shipping_amount_fen;
  final int discount_amount_fen;
  final int payable_amount_fen;
  final String policy_version_id;
  final String reservation_expires_at;
  final String status;
  final int version;
  final String created_at;
  final PaymentIntent payment;
  final CheckoutAddress address_snapshot;
  final PricingQuote pricing_snapshot;
  final List<Suborder> suborders;
  final List<InventoryReservation> reservations;
  final UnpaidCancellation? cancellation;
  const Order({required this.id, required this.order_no, required this.quote_id, required this.currency, required this.goods_amount_fen, required this.shipping_amount_fen, required this.discount_amount_fen, required this.payable_amount_fen, required this.policy_version_id, required this.reservation_expires_at, required this.status, required this.version, required this.created_at, required this.payment, required this.address_snapshot, required this.pricing_snapshot, required this.suborders, required this.reservations, required this.cancellation});
  factory Order.fromJson(Map<String,dynamic> json) => Order(
    id: json['id'] as String,
    order_no: json['order_no'] as String,
    quote_id: json['quote_id'] as String,
    currency: json['currency'] as String,
    goods_amount_fen: (json['goods_amount_fen'] as num).toInt(),
    shipping_amount_fen: (json['shipping_amount_fen'] as num).toInt(),
    discount_amount_fen: (json['discount_amount_fen'] as num).toInt(),
    payable_amount_fen: (json['payable_amount_fen'] as num).toInt(),
    policy_version_id: json['policy_version_id'] as String,
    reservation_expires_at: json['reservation_expires_at'] as String,
    status: json['status'] as String,
    version: (json['version'] as num).toInt(),
    created_at: json['created_at'] as String,
    payment: PaymentIntent.fromJson(Map<String,dynamic>.from(json['payment'] as Map)),
    address_snapshot: CheckoutAddress.fromJson(Map<String,dynamic>.from(json['address_snapshot'] as Map)),
    pricing_snapshot: PricingQuote.fromJson(Map<String,dynamic>.from(json['pricing_snapshot'] as Map)),
    suborders: (json['suborders'] as List).map((value) => Suborder.fromJson(Map<String,dynamic>.from(value as Map))).toList(),
    reservations: (json['reservations'] as List).map((value) => InventoryReservation.fromJson(Map<String,dynamic>.from(value as Map))).toList(),
    cancellation: json['cancellation'] == null ? null : UnpaidCancellation.fromJson(Map<String,dynamic>.from(json['cancellation'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'id': id,
    'order_no': order_no,
    'quote_id': quote_id,
    'currency': currency,
    'goods_amount_fen': goods_amount_fen,
    'shipping_amount_fen': shipping_amount_fen,
    'discount_amount_fen': discount_amount_fen,
    'payable_amount_fen': payable_amount_fen,
    'policy_version_id': policy_version_id,
    'reservation_expires_at': reservation_expires_at,
    'status': status,
    'version': version,
    'created_at': created_at,
    'payment': payment.toJson(),
    'address_snapshot': address_snapshot.toJson(),
    'pricing_snapshot': pricing_snapshot.toJson(),
    'suborders': suborders.map((value) => value.toJson()).toList(),
    'reservations': reservations.map((value) => value.toJson()).toList(),
    'cancellation': cancellation == null ? null : cancellation!.toJson(),
  };
}

class OrderEnvelope {
  final Order data;
  final Meta meta;
  const OrderEnvelope({required this.data, required this.meta});
  factory OrderEnvelope.fromJson(Map<String,dynamic> json) => OrderEnvelope(
    data: Order.fromJson(Map<String,dynamic>.from(json['data'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.toJson(),
    'meta': meta.toJson(),
  };
}

class OrderSummaryListEnvelope {
  final List<OrderSummary> data;
  final Page page;
  final Meta meta;
  const OrderSummaryListEnvelope({required this.data, required this.page, required this.meta});
  factory OrderSummaryListEnvelope.fromJson(Map<String,dynamic> json) => OrderSummaryListEnvelope(
    data: (json['data'] as List).map((value) => OrderSummary.fromJson(Map<String,dynamic>.from(value as Map))).toList(),
    page: Page.fromJson(Map<String,dynamic>.from(json['page'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.map((value) => value.toJson()).toList(),
    'page': page.toJson(),
    'meta': meta.toJson(),
  };
}

class SuborderListEnvelope {
  final List<Suborder> data;
  final Page page;
  final Meta meta;
  const SuborderListEnvelope({required this.data, required this.page, required this.meta});
  factory SuborderListEnvelope.fromJson(Map<String,dynamic> json) => SuborderListEnvelope(
    data: (json['data'] as List).map((value) => Suborder.fromJson(Map<String,dynamic>.from(value as Map))).toList(),
    page: Page.fromJson(Map<String,dynamic>.from(json['page'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.map((value) => value.toJson()).toList(),
    'page': page.toJson(),
    'meta': meta.toJson(),
  };
}

class SuborderEnvelope {
  final Suborder data;
  final Meta meta;
  const SuborderEnvelope({required this.data, required this.meta});
  factory SuborderEnvelope.fromJson(Map<String,dynamic> json) => SuborderEnvelope(
    data: Suborder.fromJson(Map<String,dynamic>.from(json['data'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.toJson(),
    'meta': meta.toJson(),
  };
}

class OrderPolicyEnvelope {
  final OrderPolicy data;
  final Meta meta;
  const OrderPolicyEnvelope({required this.data, required this.meta});
  factory OrderPolicyEnvelope.fromJson(Map<String,dynamic> json) => OrderPolicyEnvelope(
    data: OrderPolicy.fromJson(Map<String,dynamic>.from(json['data'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.toJson(),
    'meta': meta.toJson(),
  };
}

class PaymentAttemptInput {
  final String channel;
  final String client_platform;
  const PaymentAttemptInput({required this.channel, required this.client_platform});
  factory PaymentAttemptInput.fromJson(Map<String,dynamic> json) => PaymentAttemptInput(
    channel: json['channel'] as String,
    client_platform: json['client_platform'] as String,
  );
  Map<String,dynamic> toJson() => {
    'channel': channel,
    'client_platform': client_platform,
  };
}

class PaymentAttempt {
  final String id;
  final String payment_id;
  final String attempt_no;
  final String channel;
  final String client_platform;
  final String status;
  final int version;
  final String created_at;
  const PaymentAttempt({required this.id, required this.payment_id, required this.attempt_no, required this.channel, required this.client_platform, required this.status, required this.version, required this.created_at});
  factory PaymentAttempt.fromJson(Map<String,dynamic> json) => PaymentAttempt(
    id: json['id'] as String,
    payment_id: json['payment_id'] as String,
    attempt_no: json['attempt_no'] as String,
    channel: json['channel'] as String,
    client_platform: json['client_platform'] as String,
    status: json['status'] as String,
    version: (json['version'] as num).toInt(),
    created_at: json['created_at'] as String,
  );
  Map<String,dynamic> toJson() => {
    'id': id,
    'payment_id': payment_id,
    'attempt_no': attempt_no,
    'channel': channel,
    'client_platform': client_platform,
    'status': status,
    'version': version,
    'created_at': created_at,
  };
}

class PaymentCase {
  final String id;
  final String payment_id;
  final String attempt_id;
  final String receipt_id;
  final String reason_code;
  final String refund_no;
  final String status;
  final int attempt_count;
  final String next_retry_at;
  final String? last_error_code;
  final String created_at;
  const PaymentCase({required this.id, required this.payment_id, required this.attempt_id, required this.receipt_id, required this.reason_code, required this.refund_no, required this.status, required this.attempt_count, required this.next_retry_at, required this.last_error_code, required this.created_at});
  factory PaymentCase.fromJson(Map<String,dynamic> json) => PaymentCase(
    id: json['id'] as String,
    payment_id: json['payment_id'] as String,
    attempt_id: json['attempt_id'] as String,
    receipt_id: json['receipt_id'] as String,
    reason_code: json['reason_code'] as String,
    refund_no: json['refund_no'] as String,
    status: json['status'] as String,
    attempt_count: (json['attempt_count'] as num).toInt(),
    next_retry_at: json['next_retry_at'] as String,
    last_error_code: json['last_error_code'] == null ? null : json['last_error_code'] as String,
    created_at: json['created_at'] as String,
  );
  Map<String,dynamic> toJson() => {
    'id': id,
    'payment_id': payment_id,
    'attempt_id': attempt_id,
    'receipt_id': receipt_id,
    'reason_code': reason_code,
    'refund_no': refund_no,
    'status': status,
    'attempt_count': attempt_count,
    'next_retry_at': next_retry_at,
    'last_error_code': last_error_code == null ? null : last_error_code!,
    'created_at': created_at,
  };
}

class PaymentDetail {
  final String id;
  final String payment_no;
  final String order_id;
  final int amount_fen;
  final String currency;
  final String status;
  final String expires_at;
  final int version;
  final String created_at;
  final String? successful_attempt_id;
  final String? successful_receipt_id;
  final String? paid_at;
  final String? final_channel;
  final bool simulation;
  final List<PaymentAttempt> attempts;
  final List<PaymentCase> cases;
  const PaymentDetail({required this.id, required this.payment_no, required this.order_id, required this.amount_fen, required this.currency, required this.status, required this.expires_at, required this.version, required this.created_at, required this.successful_attempt_id, required this.successful_receipt_id, required this.paid_at, required this.final_channel, required this.simulation, required this.attempts, required this.cases});
  factory PaymentDetail.fromJson(Map<String,dynamic> json) => PaymentDetail(
    id: json['id'] as String,
    payment_no: json['payment_no'] as String,
    order_id: json['order_id'] as String,
    amount_fen: (json['amount_fen'] as num).toInt(),
    currency: json['currency'] as String,
    status: json['status'] as String,
    expires_at: json['expires_at'] as String,
    version: (json['version'] as num).toInt(),
    created_at: json['created_at'] as String,
    successful_attempt_id: json['successful_attempt_id'] == null ? null : json['successful_attempt_id'] as String,
    successful_receipt_id: json['successful_receipt_id'] == null ? null : json['successful_receipt_id'] as String,
    paid_at: json['paid_at'] == null ? null : json['paid_at'] as String,
    final_channel: json['final_channel'] == null ? null : json['final_channel'] as String,
    simulation: json['simulation'] as bool,
    attempts: (json['attempts'] as List).map((value) => PaymentAttempt.fromJson(Map<String,dynamic>.from(value as Map))).toList(),
    cases: (json['cases'] as List).map((value) => PaymentCase.fromJson(Map<String,dynamic>.from(value as Map))).toList(),
  );
  Map<String,dynamic> toJson() => {
    'id': id,
    'payment_no': payment_no,
    'order_id': order_id,
    'amount_fen': amount_fen,
    'currency': currency,
    'status': status,
    'expires_at': expires_at,
    'version': version,
    'created_at': created_at,
    'successful_attempt_id': successful_attempt_id == null ? null : successful_attempt_id!,
    'successful_receipt_id': successful_receipt_id == null ? null : successful_receipt_id!,
    'paid_at': paid_at == null ? null : paid_at!,
    'final_channel': final_channel == null ? null : final_channel!,
    'simulation': simulation,
    'attempts': attempts.map((value) => value.toJson()).toList(),
    'cases': cases.map((value) => value.toJson()).toList(),
  };
}

class SimulationInput {
  final String attempt_id;
  final String outcome;
  const SimulationInput({required this.attempt_id, required this.outcome});
  factory SimulationInput.fromJson(Map<String,dynamic> json) => SimulationInput(
    attempt_id: json['attempt_id'] as String,
    outcome: json['outcome'] as String,
  );
  Map<String,dynamic> toJson() => {
    'attempt_id': attempt_id,
    'outcome': outcome,
  };
}

class PaymentDetailEnvelope {
  final PaymentDetail data;
  final Meta meta;
  const PaymentDetailEnvelope({required this.data, required this.meta});
  factory PaymentDetailEnvelope.fromJson(Map<String,dynamic> json) => PaymentDetailEnvelope(
    data: PaymentDetail.fromJson(Map<String,dynamic>.from(json['data'] as Map)),
    meta: Meta.fromJson(Map<String,dynamic>.from(json['meta'] as Map)),
  );
  Map<String,dynamic> toJson() => {
    'data': data.toJson(),
    'meta': meta.toJson(),
  };
}

class ApiRoutes {
  static const post_consumer_auth_phone_request_code = '/consumer/auth/phone/request-code';
  static const post_consumer_auth_phone_verify = '/consumer/auth/phone/verify';
  static const post_consumer_auth_refresh = '/consumer/auth/refresh';
  static const post_consumer_auth_reverify = '/consumer/auth/reverify';
  static const post_consumer_auth_logout = '/consumer/auth/logout';
  static const get_consumer_me = '/consumer/me';
  static const get_consumer_auth_sessions = '/consumer/auth/sessions';
  static const delete_consumer_auth_sessions_session_id = '/consumer/auth/sessions/{session_id}';
  static const post_consumer_auth_sessions_revoke_others = '/consumer/auth/sessions/revoke-others';
  static const post_merchant_auth_login = '/merchant/auth/login';
  static const post_merchant_auth_refresh = '/merchant/auth/refresh';
  static const post_merchant_auth_reverify = '/merchant/auth/reverify';
  static const post_merchant_auth_logout = '/merchant/auth/logout';
  static const get_merchant_me = '/merchant/me';
  static const get_merchant_auth_sessions = '/merchant/auth/sessions';
  static const delete_merchant_auth_sessions_session_id = '/merchant/auth/sessions/{session_id}';
  static const post_merchant_auth_sessions_revoke_others = '/merchant/auth/sessions/revoke-others';
  static const post_admin_auth_login = '/admin/auth/login';
  static const post_admin_auth_refresh = '/admin/auth/refresh';
  static const post_admin_auth_reverify = '/admin/auth/reverify';
  static const post_admin_auth_logout = '/admin/auth/logout';
  static const get_admin_me = '/admin/me';
  static const get_admin_auth_sessions = '/admin/auth/sessions';
  static const delete_admin_auth_sessions_session_id = '/admin/auth/sessions/{session_id}';
  static const post_admin_auth_sessions_revoke_others = '/admin/auth/sessions/revoke-others';
  static const get_merchant_stores = '/merchant/stores';
  static const get_merchant_stores_store_id = '/merchant/stores/{store_id}';
  static const get_admin_access_roles = '/admin/access/roles';
  static const post_admin_access_roles = '/admin/access/roles';
  static const patch_admin_access_roles_role_id = '/admin/access/roles/{role_id}';
  static const get_admin_audit = '/admin/audit';
  static const list_outbox = '/admin/operations/outbox';
  static const outbox_stats = '/admin/operations/outbox/stats';
  static const replay_outbox = '/admin/operations/outbox/{event_id}/replay';
  static const issue_media_upload_grant = '/media/upload-grants';
  static const upload_media_content = '/media/{asset_id}/content';
  static const read_media_content = '/media/{asset_id}/content';
  static const get_media_metadata = '/media/{asset_id}';
  static const delete_media_asset = '/media/{asset_id}';
  static const get_search_operations = '/admin/operations/search';
  static const search_rebuild = '/admin/operations/search/rebuild';
  static const search_reconcile = '/admin/operations/search/reconcile';
  static const search_retry = '/admin/operations/search/retry';
  static const get_public_pet_taxonomy = '/public/pet-taxonomy';
  static const get_public_pet_species__species_id__breeds = '/public/pet-species/{species_id}/breeds';
  static const get_public_allergens = '/public/allergens';
  static const get_consumer_pets = '/consumer/pets';
  static const post_consumer_pets = '/consumer/pets';
  static const get_consumer_pets__pet_id = '/consumer/pets/{pet_id}';
  static const patch_consumer_pets__pet_id = '/consumer/pets/{pet_id}';
  static const delete_consumer_pets__pet_id = '/consumer/pets/{pet_id}';
  static const get_consumer_pets__pet_id__weight_records = '/consumer/pets/{pet_id}/weight-records';
  static const post_consumer_pets__pet_id__weight_records = '/consumer/pets/{pet_id}/weight-records';
  static const get_admin_pet_taxonomy = '/admin/pet-taxonomy';
  static const post_admin_pet_taxonomy_species = '/admin/pet-taxonomy/species';
  static const post_admin_pet_taxonomy_breeds = '/admin/pet-taxonomy/breeds';
  static const post_admin_pet_taxonomy_allergens = '/admin/pet-taxonomy/allergens';
  static const post_admin_pet_taxonomy_life_stage_rules = '/admin/pet-taxonomy/life-stage-rules';
  static const post_admin_pet_taxonomy_species__id__retire = '/admin/pet-taxonomy/species/{id}/retire';
  static const post_admin_pet_taxonomy_breeds__id__retire = '/admin/pet-taxonomy/breeds/{id}/retire';
  static const post_admin_pet_taxonomy_allergens__id__retire = '/admin/pet-taxonomy/allergens/{id}/retire';
  static const get_admin_brands = '/admin/brands';
  static const post_admin_brands = '/admin/brands';
  static const get_admin_spus = '/admin/spus';
  static const post_admin_spus = '/admin/spus';
  static const get_admin_skus = '/admin/skus';
  static const post_admin_skus = '/admin/skus';
  static const get_admin_skus__id = '/admin/skus/{id}';
  static const get_merchant_catalog_search = '/merchant/catalog/search';
  static const get_merchant_catalog_skus__id = '/merchant/catalog/skus/{id}';
  static const post_admin_skus__id__standard_versions = '/admin/skus/{id}/standard-versions';
  static const post_admin_sku_standard_versions__id__publish = '/admin/sku-standard-versions/{id}/publish';
  static const post_merchant_catalog_requests = '/merchant/catalog-requests';
  static const get_merchant_catalog_requests = '/merchant/catalog-requests';
  static const get_merchant_catalog_requests__id = '/merchant/catalog-requests/{id}';
  static const get_admin_catalog_reviews = '/admin/catalog-reviews';
  static const get_admin_catalog_reviews__id = '/admin/catalog-reviews/{id}';
  static const post_admin_catalog_reviews__id__approve = '/admin/catalog-reviews/{id}/approve';
  static const post_admin_catalog_reviews__id__reject = '/admin/catalog-reviews/{id}/reject';
  static const post_admin_catalog_imports = '/admin/catalog-imports';
  static const get_admin_catalog_imports__id = '/admin/catalog-imports/{id}';
  static const post_admin_catalog_imports__id__confirm = '/admin/catalog-imports/{id}/confirm';
  static const post_admin_catalog_imports__id__cancel = '/admin/catalog-imports/{id}/cancel';
  static const get_merchant_offers = '/merchant/offers';
  static const post_merchant_offers = '/merchant/offers';
  static const get_merchant_offers__id = '/merchant/offers/{id}';
  static const patch_merchant_offers__id = '/merchant/offers/{id}';
  static const get_merchant_offers__id__inventory_adjustments = '/merchant/offers/{id}/inventory-adjustments';
  static const post_merchant_offers__id__inventory_adjustments = '/merchant/offers/{id}/inventory-adjustments';
  static const get_admin_offers = '/admin/offers';
  static const get_admin_offers__id = '/admin/offers/{id}';
  static const get_admin_offers__id__inventory_adjustments = '/admin/offers/{id}/inventory-adjustments';
  static const post_merchant_offers_batch = '/merchant/offers/batch';
  static const post_merchant_offers__id__activate = '/merchant/offers/{id}/activate';
  static const post_merchant_offers__id__pause = '/merchant/offers/{id}/pause';
  static const post_admin_offers__id__freeze = '/admin/offers/{id}/freeze';
  static const post_admin_offers__id__unfreeze = '/admin/offers/{id}/unfreeze';
  static const post_admin_offers__id__delist = '/admin/offers/{id}/delist';
  static const get_public_spus__id = '/public/spus/{id}';
  static const get_public_skus__id = '/public/skus/{id}';
  static const get_public_skus__id__offers = '/public/skus/{id}/offers';
  static const get_public_products = '/public/products';
  static const get_consumer_spus__id = '/consumer/spus/{id}';
  static const get_consumer_skus__id = '/consumer/skus/{id}';
  static const get_consumer_skus__id__offers = '/consumer/skus/{id}/offers';
  static const get_consumer_products = '/consumer/products';
  static const get_consumer_skus__id__fit = '/consumer/skus/{id}/fit';
  static const post_consumer_products_compare = '/consumer/products/compare';
  static const get_consumer_cart = '/consumer/cart';
  static const get_consumer_checkout_benefits = '/consumer/checkout/benefits';
  static const post_consumer_cart_items = '/consumer/cart/items';
  static const patch_consumer_cart_items__id = '/consumer/cart/items/{id}';
  static const delete_consumer_cart_items__id = '/consumer/cart/items/{id}';
  static const post_consumer_cart_merge_guest_intent = '/consumer/cart/merge-guest-intent';
  static const get_consumer_addresses = '/consumer/addresses';
  static const post_consumer_addresses = '/consumer/addresses';
  static const patch_consumer_addresses__id = '/consumer/addresses/{id}';
  static const delete_consumer_addresses__id = '/consumer/addresses/{id}';
  static const post_consumer_checkout_quotes = '/consumer/checkout/quotes';
  static const get_consumer_checkout_quotes__id = '/consumer/checkout/quotes/{id}';
  static const get_admin_merchants__id__shipping_rules = '/admin/merchants/{id}/shipping-rules';
  static const post_admin_merchants__id__shipping_rules = '/admin/merchants/{id}/shipping-rules';
  static const post_consumer_orders = '/consumer/orders';
  static const get_consumer_orders = '/consumer/orders';
  static const get_consumer_orders__id = '/consumer/orders/{id}';
  static const post_consumer_orders__id__cancel = '/consumer/orders/{id}/cancel';
  static const get_merchant_suborders = '/merchant/suborders';
  static const get_merchant_suborders__id = '/merchant/suborders/{id}';
  static const get_admin_orders = '/admin/orders';
  static const get_admin_orders__id = '/admin/orders/{id}';
  static const get_admin_order_policies = '/admin/order-policies';
  static const post_admin_order_policies = '/admin/order-policies';
  static const get_consumer_payments__id = '/consumer/payments/{id}';
  static const get_consumer_payments__id__status = '/consumer/payments/{id}/status';
  static const post_consumer_payments__id__attempts = '/consumer/payments/{id}/attempts';
  static const post_consumer_payments__id__close_attempt = '/consumer/payments/{id}/close-attempt';
  static const post_consumer_payments__id__requery = '/consumer/payments/{id}/requery';
  static const get_admin_payments__id = '/admin/payments/{id}';
  static const post_admin_payments__id__requery = '/admin/payments/{id}/requery';
  static const post_consumer_payments__id__simulation = '/consumer/payments/{id}/simulation';
}
