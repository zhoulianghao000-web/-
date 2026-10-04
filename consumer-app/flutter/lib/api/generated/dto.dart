// Generated from pawday-m2.3.yaml; SHA256 d599a3d470802332e2fcbd6f0b565b055b917b596cc51cd231a6bbd219b7d12b
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
}
