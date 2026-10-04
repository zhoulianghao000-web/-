// Generated from pawday-m3.1.yaml; SHA256 f93a0b0f6f09982e77f7d53cb8286366892c9ca6c3e35d74fc1552e690ba1db0
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
}
