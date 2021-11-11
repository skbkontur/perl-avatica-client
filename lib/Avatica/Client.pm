package Avatica::Client;

use strict;
use warnings;
use Carp 'croak';
use HTTP::Tiny;
use Time::HiRes qw/sleep/;

use Google::ProtocolBuffers::Dynamic;

use constant MAX_RETRIES => 1;
use constant CLASS_REQUEST_PREFIX => 'org.apache.calcite.avatica.proto.Requests$';

sub new {
  my ($class, %params) = @_;
  croak q{param "url" is required} unless $params{url};
  my $ua = $params{ua} // HTTP::Tiny->new;

  my $self = {
    url => $params{url},
    max_retries => $params{max_retries} // $class->MAX_RETRIES,
    ua => $ua
  };
  return bless $self, $class;
}

sub url { $_[0]->{url} }
sub ua { $_[0]->{ua} }
sub max_retries { $_[0]->{max_retries} }
sub headers { +{'Content-Type' => 'application/x-google-protobuf'} }

sub apply {
  my ($self, $request_name, $request) = @_;

  my $body = $self->wrap_request($request_name, $request);

  my ($status, $response_body) = $self->post_request($body);
  if (int($status / 100) != 2) {
    # network errors
    return 0, {message => $response_body} if $status == 599;
    # other errors
    return 0, $self->parse_error($response_body);
  }
  my $response = $self->unwrap_response($response_body);
  return 1, $response;
}

sub post_request {
  my ($self, $body) = @_;

  my $response;
  my $retry_count = $self->max_retries;
  while ($retry_count > 0) {
    $retry_count--;

    $response = $self->ua->post($self->url, {
      headers => $self->headers,
      content => $body
    });

    unless ($response->{success}) {
      if (int($response->{status} / 100) == 5) {
        sleep(exp -$retry_count);
        next;
      }
    }
    last;
  }

  return @$response{qw/status content/};
}

# params: self, request_name, request
sub wrap_request {
  my ($self, $request_name, $request) = @_;
  my $wire_msg = Avatica::Client::Protocol::WireMessage->new;
  $wire_msg->set_name($self->CLASS_REQUEST_PREFIX . $request_name);
  $wire_msg->set_wrapped_message($request);
  return Avatica::Client::Protocol::WireMessage->encode($wire_msg);
}

sub unwrap_response {
  my ($self, $response_body) = @_;
  my $wire_msg = Avatica::Client::Protocol::WireMessage->decode($response_body);
  return $wire_msg->get_wrapped_message;
}

sub parse_error {
  my ($self, $response_body) = @_;
  my $response_encoded = $self->unwrap_response($response_body);
  my $error = Avatica::Client::Protocol::ErrorResponse->decode($response_encoded);
  my $msg = {
    message => $error->get_error_message,
    protocol => {
      message => $error->get_error_message,
      severity => $error->get_severity,
      error_code => $error->get_error_code,
      sql_state => $error->get_sql_state
    }
  };
  $msg->{protocol}{exceptions} = $error->get_exceptions_list if $error->get_has_exceptions;
  return $msg;
}

sub open_connection {
  my ($self, $connection_id, $info) = @_;

  my $c = Avatica::Client::Protocol::OpenConnectionRequest->new;
  $c->set_connection_id($connection_id);
  $c->set_info_map($info) if $info;
  my $msg = Avatica::Client::Protocol::OpenConnectionRequest->encode($c);

  my ($res, $response) = $self->apply('OpenConnectionRequest', $msg);
  return ($res, $response) unless $res;

  $response = Avatica::Client::Protocol::OpenConnectionResponse->decode($response);
  return ($res, $response);
}

sub close_connection {
  my ($self, $connection_id) = @_;

  my $c = Avatica::Client::Protocol::CloseConnectionRequest->new;
  $c->set_connection_id($connection_id);
  my $msg = Avatica::Client::Protocol::CloseConnectionRequest->encode($c);

  my ($res, $response) = $self->apply('CloseConnectionRequest', $msg);
  return ($res, $response) unless $res;

  $response = Avatica::Client::Protocol::CloseConnectionResponse->decode($response);
  return ($res, $response);
}

sub catalog {
  my ($self, $connection_id) = @_;

  my $c = Avatica::Client::Protocol::CatalogsRequest->new;
  $c->set_connection_id($connection_id);
  my $msg = Avatica::Client::Protocol::CatalogsRequest->encode($c);

  my ($res, $response) = $self->apply('CatalogsRequest', $msg);
  return ($res, $response) unless $res;

  $response = Avatica::Client::Protocol::ResultSetResponse->decode($response);
  return ($res, $response);
}

sub columns {
  my ($self, $connection_id, $catalog, $schema_pattern, $table_pattern, $column_pattern) = @_;

  my $c = Avatica::Client::Protocol::ColumnsRequest->new;
  $c->set_connection_id($connection_id);
  if ($catalog) {
    $c->set_catalog($catalog);
    $c->set_has_catalog(1);
  }
  if ($schema_pattern) {
    $c->set_schema_pattern($schema_pattern);
    $c->set_has_schema_pattern(1);
  }
  if ($table_pattern) {
    $c->set_table_name_pattern($table_pattern);
    $c->set_has_table_name_pattern(1);
  }
  if ($column_pattern) {
    $c->set_column_name_pattern($column_pattern);
    $c->set_has_column_name_pattern(1);
  }
  my $msg = Avatica::Client::Protocol::ColumnsRequest->encode($c);

  my ($res, $response) = $self->apply('ColumnsRequest', $msg);
  return ($res, $response) unless $res;

  $response = Avatica::Client::Protocol::ResultSetResponse->decode($response);
  return ($res, $response);
}

sub database_property {
  my ($self, $connection_id) = @_;

  my $d = Avatica::Client::Protocol::DatabasePropertyRequest->new;
  $d->set_connection_id($connection_id);
  my $msg = Avatica::Client::Protocol::DatabasePropertyRequest->encode($d);

  my ($res, $response) = $self->apply('DatabasePropertyRequest', $msg);
  return ($res, $response) unless $res;

  $response = Avatica::Client::Protocol::DatabasePropertyResponse->decode($response);
  return ($res, $response);
}

sub schemas {
  my ($self, $connection_id, $catalog, $schema_pattern) = @_;

  my $s = Avatica::Client::Protocol::SchemasRequest->new;
  $s->set_connection_id($connection_id);
  if ($catalog) {
    $s->set_catalog($catalog);
    $s->set_has_catalog(1);
  }
  if ($schema_pattern) {
    $s->set_schema_pattern($schema_pattern);
    $s->set_has_schema_pattern(1);
  }
  my $msg = Avatica::Client::Protocol::SchemasRequest->encode($s);

  my ($res, $response) = $self->apply('SchemasRequest', $msg);
  return ($res, $response) unless $res;

  $response = Avatica::Client::Protocol::ResultSetResponse->decode($response);
  return ($res, $response);
}

sub tables {
  my ($self, $connection_id, $catalog, $schema_pattern, $table_pattern, $type_list) = @_;

  my $t = Avatica::Client::Protocol::TablesRequest->new;
  $t->set_connection_id($connection_id);
  if ($catalog) {
    $t->set_catalog($catalog);
    $t->set_has_catalog(1);
  }
  if ($schema_pattern) {
    $t->set_schema_pattern($schema_pattern);
    $t->set_has_schema_pattern(1);
  }
  if ($table_pattern) {
    $t->set_table_name_pattern($table_pattern);
    $t->set_has_table_name_pattern(1);
  }
  if ($type_list) {
    $t->set_type_list($type_list);
    $t->set_has_type_list(1);
  }
  my $msg = Avatica::Client::Protocol::TablesRequest->encode($t);

  my ($res, $response) = $self->apply('TablesRequest', $msg);
  return ($res, $response) unless $res;

  $response = Avatica::Client::Protocol::ResultSetResponse->decode($response);
  return ($res, $response);
}

sub type_info {
  my ($self, $connection_id) = @_;

  my $t = Avatica::Client::Protocol::TypeInfoRequest->new;
  $t->set_connection_id($connection_id);
  my $msg = Avatica::Client::Protocol::TypeInfoRequest->encode($t);

  my ($res, $response) = $self->apply('TypeInfoRequest', $msg);
  return ($res, $response) unless $res;

  $response = Avatica::Client::Protocol::ResultSetResponse->decode($response);
  return ($res, $response);
}

sub connection_sync {
  my ($self, $connection_id, $props) = @_;

  my $p = Avatica::Client::Protocol::ConnectionProperties->new;
  if (exists $props->{AutoCommit}) {
    $p->set_auto_commit($props->{AutoCommit});
    $p->set_has_auto_commit(1);
  }
  if (exists $props->{ReadOnly}) {
    $p->set_read_only($props->{ReadOnly});
    $p->set_has_read_only(1);
  }
  if (exists $props->{TransactionIsolation}) {
    $p->set_transaction_isolation($props->{TransactionIsolation});
  }
  if (exists $props->{Catalog}) {
    $p->set_catalog($props->{Catalog});
  }
  if (exists $props->{Schema}) {
    $p->set_schema($props->{Schema});
  }

  my $c = Avatica::Client::Protocol::ConnectionSyncRequest->new;
  $c->set_connection_id($connection_id);
  $c->set_conn_props($p);
  my $msg = Avatica::Client::Protocol::ConnectionSyncRequest->encode($c);

  my ($res, $response) = $self->apply('ConnectionSyncRequest', $msg);
  return ($res, $response) unless $res;

  $response = Avatica::Client::Protocol::ConnectionSyncResponse->decode($response);
  return ($res, $response);
}

sub create_statement {
  my ($self, $connection_id) = @_;

  my $s = Avatica::Client::Protocol::CreateStatementRequest->new;
  $s->set_connection_id($connection_id);
  my $msg = Avatica::Client::Protocol::CreateStatementRequest->encode($s);

  my ($res, $response) = $self->apply('CreateStatementRequest', $msg);
  return ($res, $response) unless $res;

  $response = Avatica::Client::Protocol::CreateStatementResponse->decode($response);
  return ($res, $response);
}

sub close_statement {
  my ($self, $connection_id, $statement_id) = @_;

  my $c = Avatica::Client::Protocol::CloseStatementRequest->new;
  $c->set_connection_id($connection_id);
  $c->set_statement_id($statement_id);
  my $msg = Avatica::Client::Protocol::CloseStatementRequest->encode($c);

  my ($res, $response) = $self->apply('CloseStatementRequest', $msg);
  return ($res, $response) unless $res;

  $response = Avatica::Client::Protocol::CloseStatementResponse->decode($response);
  return ($res, $response);
}

sub prepare_and_execute {
  my ($self, $connection_id, $statement_id, $sql, $max_rows_total, $first_frame_max_size) = @_;

  my $pe = Avatica::Client::Protocol::PrepareAndExecuteRequest->new;
  $pe->set_connection_id($connection_id);
  $pe->set_statement_id($statement_id);
  $pe->set_sql($sql);
  $pe->set_max_rows_total($max_rows_total) if $max_rows_total;
  $pe->set_first_frame_max_size($first_frame_max_size) if $first_frame_max_size;
  my $msg = Avatica::Client::Protocol::PrepareAndExecuteRequest->encode($pe);

  my ($res, $response) = $self->apply('PrepareAndExecuteRequest', $msg);
  return ($res, $response) unless $res;

  $response = Avatica::Client::Protocol::ExecuteResponse->decode($response);
  return 0, {message => 'missing statement id'} if $response->get_missing_statement;

  return ($res, $response);
}

sub prepare {
  my ($self, $connection_id, $sql, $max_rows_total) = @_;

  my $p = Avatica::Client::Protocol::PrepareRequest->new;
  $p->set_connection_id($connection_id);
  $p->set_sql($sql);
  $p->set_max_rows_total($max_rows_total) if $max_rows_total;
  my $msg = Avatica::Client::Protocol::PrepareRequest->encode($p);

  my ($res, $response) = $self->apply('PrepareRequest', $msg);
  return ($res, $response) unless $res;

  $response = Avatica::Client::Protocol::PrepareResponse->decode($response);

  return ($res, $response);
}

sub execute {
  my ($self, $connection_id, $statement_id, $signature, $param_values, $first_frame_max_size) = @_;

  my $sh = Avatica::Client::Protocol::StatementHandle->new;
  $sh->set_id($statement_id);
  $sh->set_connection_id($connection_id);
  $sh->set_signature($signature);

  my $e = Avatica::Client::Protocol::ExecuteRequest->new;
  $e->set_statementHandle($sh);
  if ($param_values && @$param_values) {
    $e->set_parameter_values_list($param_values);
    $e->set_has_parameter_values(1);
  }
  if ($first_frame_max_size) {
    $e->set_first_frame_max_size($first_frame_max_size);
    $e->set_deprecated_first_frame_max_size($first_frame_max_size);
  }

  my $msg = Avatica::Client::Protocol::ExecuteRequest->encode($e);

  my ($res, $response) = $self->apply('ExecuteRequest', $msg);
  return ($res, $response) unless $res;

  $response = Avatica::Client::Protocol::ExecuteResponse->decode($response);
  return 0, {message => 'missing statement id'} if $response->get_missing_statement;

  return ($res, $response);
}

# prepare and execute batch of **UPDATES**
sub prepare_and_execute_batch {
  my ($self, $connection_id, $statement_id, $sqls) = @_;

  my $p = Avatica::Client::Protocol::PrepareAndExecuteBatchRequest->new;
  $p->set_connection_id($connection_id);
  $p->set_statement_id($statement_id);
  for my $sql (@$sqls) {
    $p->add_sql_commands($sql);
  }
  my $msg = Avatica::Client::Protocol::PrepareAndExecuteBatchRequest->encode($p);

  my ($res, $response) = $self->apply('PrepareAndExecuteBatchRequest', $msg);
  return ($res, $response) unless $res;

  $response = Avatica::Client::Protocol::ExecuteBatchResponse->decode($response);
  return 0, {message => 'missing statement id'} if $response->get_missing_statement;
  return ($res, $response);
}

# execute batch of **UPDATES**
sub execute_batch {
  my ($self, $connection_id, $statement_id, $rows) = @_;

  my $eb = Avatica::Client::Protocol::ExecuteBatchRequest->new;
  $eb->set_connection_id($connection_id);
  $eb->set_statement_id($statement_id);
  for my $row (@{$rows // []}) {
    my $ub = Avatica::Client::Protocol::UpdateBatch->new;
    for my $col (@$row) {
      $ub->add_parameter_values($col);
    }
    $eb->add_updates($ub);
  }
  my $msg = Avatica::Client::Protocol::ExecuteBatchRequest->encode($eb);

  my ($res, $response) = $self->apply('ExecuteBatchRequest', $msg);
  return ($res, $response) unless $res;

  $response = Avatica::Client::Protocol::ExecuteBatchResponse->decode($response);
  return 0, {message => 'missing statement id'} if $response->get_missing_statement;
  return ($res, $response);
}

sub fetch {
  my ($self, $connection_id, $statement_id, $offset, $frame_max_size) = @_;

  my $f = Avatica::Client::Protocol::FetchRequest->new;
  $f->set_connection_id($connection_id);
  $f->set_statement_id($statement_id);
  $f->set_offset($offset) if defined $offset;
  $f->set_frame_max_size($frame_max_size) if $frame_max_size;
  my $msg = Avatica::Client::Protocol::FetchRequest->encode($f);

  my ($res, $response) = $self->apply('FetchRequest', $msg);
  return ($res, $response) unless $res;

  $response = Avatica::Client::Protocol::FetchResponse->decode($response);

  return 0, {message => 'missing statement id'} if $response->get_missing_statement;
  return 0, {message => 'missing result set'} if $response->get_missing_results;

  return ($res, $response);
}

sub sync_results {
  my ($self, $connection_id, $statement_id, $state, $offset) = @_;

  my $s = Avatica::Client::Protocol::SyncResultsRequest->new;
  $s->set_connection_id($connection_id);
  $s->set_statement_id($statement_id);
  $s->set_state($state);
  $s->set_offset($offset) if defined $offset;
  my $msg = Avatica::Client::Protocol::SyncResultsRequest->encode($s);

  my ($res, $response) = $self->apply('SyncResultsRequest', $msg);
  return ($res, $response) unless $res;

  $response = Avatica::Client::Protocol::SyncResultsResponse->decode($response);
  return 0, {message => 'missing statement id'} if $response->get_missing_statement;
  return ($res, $response);
}

sub _data_section {
  my $class = shift;
  my $handle = do { no strict 'refs'; \*{"${class}::DATA"} };
  return unless fileno $handle;
  seek $handle, 0, 0;
  local $/ = undef;
  my $data = <$handle>;
  $data =~ s/^.*\n__DATA__\r?\n//s;
  $data =~ s/\r?\n__END__\r?\n.*$//s;
  return $data;
}

my $dynamic = Google::ProtocolBuffers::Dynamic->new;
$dynamic->load_string("avatica.proto", _data_section(__PACKAGE__));
$dynamic->map({ package => 'Avatica.Client.Protocol', prefix => 'Avatica::Client::Protocol' });

1;

__DATA__
syntax = "proto3";

package Avatica.Client.Protocol;

message OpenConnectionRequest {
  string connection_id = 1;
  map<string, string> info = 2;
}

message OpenConnectionResponse {
  RpcMetadata metadata = 1;
}

message CloseConnectionRequest {
  string connection_id = 1;
}

message CloseConnectionResponse {
  RpcMetadata metadata = 1;
}

message CatalogsRequest {
  string connection_id = 1;
}

message ColumnsRequest {
  string catalog = 1;
  string schema_pattern = 2;
  string table_name_pattern = 3;
  string column_name_pattern = 4;
  string connection_id = 5;
  bool   has_catalog = 6;
  bool   has_schema_pattern = 7;
  bool   has_table_name_pattern = 8;
  bool   has_column_name_pattern = 9;
}

message TypeInfoRequest {
  string connection_id = 1;
}

message SchemasRequest {
  string catalog = 1;
  string schema_pattern = 2;
  string connection_id = 3;
  bool   has_catalog = 4;
  bool   has_schema_pattern = 5;
}

message TablesRequest {
  string catalog = 1;
  string schema_pattern = 2;
  string table_name_pattern = 3;
  repeated string type_list = 4;
  bool has_type_list = 6;
  string connection_id = 7;
  bool   has_catalog = 8;
  bool   has_schema_pattern = 9;
  bool   has_table_name_pattern = 10;
}

message ConnectionSyncRequest {
  string connection_id = 1;
  ConnectionProperties conn_props = 2;
}

message ConnectionSyncResponse {
  ConnectionProperties conn_props = 1;
  RpcMetadata metadata = 2;
}

message DatabasePropertyRequest {
  string connection_id = 1;
}

message DatabasePropertyResponse {
  repeated DatabaseProperty props = 1;
  RpcMetadata metadata = 2;
}

message CreateStatementRequest {
  string connection_id = 1;
}

message CreateStatementResponse {
  string connection_id = 1;
  uint32 statement_id = 2;
  RpcMetadata metadata = 3;
}

message CloseStatementRequest {
  string connection_id = 1;
  uint32 statement_id = 2;
}

message CloseStatementResponse {
  RpcMetadata metadata = 1;
}

message PrepareAndExecuteRequest {
  string connection_id = 1;
  uint32 statement_id = 4;
  string sql = 2;
  uint64 max_row_count = 3; // Deprecated!
  int64 max_rows_total = 5;
  int32 first_frame_max_size = 6;
}

message PrepareAndExecuteBatchRequest {
  string connection_id = 1;
  uint32 statement_id = 2;
  repeated string sql_commands = 3;
}

message PrepareRequest {
  string connection_id = 1;
  string sql = 2;
  uint64 max_row_count = 3; // Deprecated!
  int64 max_rows_total = 4;
}

message PrepareResponse {
  StatementHandle statement = 1;
  RpcMetadata metadata = 2;
}

message ExecuteRequest {
  StatementHandle statementHandle = 1;
  repeated TypedValue parameter_values = 2;
  uint64 deprecated_first_frame_max_size = 3;
  bool has_parameter_values = 4;
  int32 first_frame_max_size = 5;
}

message ExecuteResponse {
  repeated ResultSetResponse results = 1;
  bool missing_statement = 2;
  RpcMetadata metadata = 3;
}

message ExecuteBatchRequest {
  string connection_id = 1;
  uint32 statement_id = 2;
  repeated UpdateBatch updates = 3;
}

message ExecuteBatchResponse {
  string connection_id = 1;
  uint32 statement_id = 2;
  repeated uint32 update_counts = 3;
  bool missing_statement = 4;
  RpcMetadata metadata = 5;
}

message ResultSetResponse {
  string connection_id = 1;
  uint32 statement_id = 2;
  bool own_statement = 3;
  Signature signature = 4;
  Frame first_frame = 5;
  uint64 update_count = 6;
  RpcMetadata metadata = 7;
}

message FetchRequest {
  string connection_id = 1;
  uint32 statement_id = 2;
  uint64 offset = 3;
  uint32 fetch_max_row_count = 4; // Deprecated!
  int32 frame_max_size = 5;
}

message FetchResponse {
  Frame frame = 1;
  bool missing_statement = 2;
  bool missing_results = 3;
  RpcMetadata metadata = 4;
}

message SyncResultsRequest {
  string connection_id = 1;
  uint32 statement_id = 2;
  QueryState state = 3;
  uint64 offset = 4;
}

message SyncResultsResponse {
  bool missing_statement = 1;
  bool more_results = 2;
  RpcMetadata metadata = 3;
}

message ErrorResponse {
  repeated string exceptions = 1;
  bool has_exceptions = 7;
  string error_message = 2;
  Severity severity = 3;
  uint32 error_code = 4;
  string sql_state = 5;
  RpcMetadata metadata = 6;
}

message QueryState {
  StateType type = 1;
  string sql = 2;
  MetaDataOperation op = 3;
  repeated MetaDataOperationArgument args = 4;
  bool has_args = 5;
  bool has_sql = 6;
  bool has_op = 7;
}

enum StateType {
  SQL = 0;
  METADATA = 1;
}

// Enumeration corresponding to DatabaseMetaData operations
enum MetaDataOperation {
  GET_ATTRIBUTES = 0;
  GET_BEST_ROW_IDENTIFIER = 1;
  GET_CATALOGS = 2;
  GET_CLIENT_INFO_PROPERTIES = 3;
  GET_COLUMN_PRIVILEGES = 4;
  GET_COLUMNS = 5;
  GET_CROSS_REFERENCE = 6;
  GET_EXPORTED_KEYS = 7;
  GET_FUNCTION_COLUMNS = 8;
  GET_FUNCTIONS = 9;
  GET_IMPORTED_KEYS = 10;
  GET_INDEX_INFO = 11;
  GET_PRIMARY_KEYS = 12;
  GET_PROCEDURE_COLUMNS = 13;
  GET_PROCEDURES = 14;
  GET_PSEUDO_COLUMNS = 15;
  GET_SCHEMAS = 16;
  GET_SCHEMAS_WITH_ARGS = 17;
  GET_SUPER_TABLES = 18;
  GET_SUPER_TYPES = 19;
  GET_TABLE_PRIVILEGES = 20;
  GET_TABLES = 21;
  GET_TABLE_TYPES = 22;
  GET_TYPE_INFO = 23;
  GET_UDTS = 24;
  GET_VERSION_COLUMNS = 25;
}

// Represents the breadth of arguments to DatabaseMetaData functions
message MetaDataOperationArgument {
  enum ArgumentType {
    STRING = 0;
    BOOL = 1;
    INT = 2;
    REPEATED_STRING = 3;
    REPEATED_INT = 4;
    NULL = 5;
  }

  string string_value = 1;
  bool bool_value = 2;
  sint32 int_value = 3;
  repeated string string_array_values = 4;
  repeated sint32 int_array_values = 5;
  ArgumentType type = 6;
}

message UpdateBatch {
  repeated TypedValue parameter_values = 1;
}

// Database property, list of functions the database provides for a certain operation
message DatabaseProperty {
  string name = 1;
  repeated string functions = 2;
}

// Details about a connection
message ConnectionProperties {
  bool is_dirty = 1;
  bool auto_commit = 2;
  bool has_auto_commit = 7; // field is a Boolean, need to discern null and default value
  bool read_only = 3;
  bool has_read_only = 8; // field is a Boolean, need to discern null and default value
  uint32 transaction_isolation = 4;
  string catalog = 5;
  string schema = 6;
}

// The severity of some unexpected outcome to an operation.
// Protobuf enum values must be unique across all other enums
enum Severity {
  UNKNOWN_SEVERITY = 0;
  FATAL_SEVERITY = 1;
  ERROR_SEVERITY = 2;
  WARNING_SEVERITY = 3;
}

// A collection of rows
message Frame {
  uint64 offset = 1;
  bool done = 2;
  repeated Row rows = 3;
}

// A row is a collection of values
message Row {
  repeated ColumnValue value = 1;
}

// A value might be a TypedValue or an Array of TypedValue's
message ColumnValue {
  repeated TypedValue value = 1; // deprecated, use array_value or scalar_value
  repeated TypedValue array_value = 2;
  bool has_array_value = 3; // Is an array value set?
  TypedValue scalar_value = 4;
}

// Statement handle
message StatementHandle {
  string connection_id = 1;
  uint32 id = 2;
  Signature signature = 3;
}

// Results of preparing a statement
message Signature {
  repeated ColumnMetaData columns = 1;
  string sql = 2;
  repeated AvaticaParameter parameters = 3;
  CursorFactory cursor_factory = 4;
  StatementType statementType = 5;
}

message ColumnMetaData {
  uint32 ordinal = 1;
  bool auto_increment = 2;
  bool case_sensitive = 3;
  bool searchable = 4;
  bool currency = 5;
  uint32 nullable = 6;
  bool signed = 7;
  uint32 display_size = 8;
  string label = 9;
  string column_name = 10;
  string schema_name = 11;
  uint32 precision = 12;
  uint32 scale = 13;
  string table_name = 14;
  string catalog_name = 15;
  bool read_only = 16;
  bool writable = 17;
  bool definitely_writable = 18;
  string column_class_name = 19;
  AvaticaType type = 20;
}

// Metadata for a parameter
message AvaticaParameter {
  bool signed = 1;
  uint32 precision = 2;
  uint32 scale = 3;
  uint32 parameter_type = 4;
  string type_name = 5;
  string class_name = 6;
  string name = 7;
}

// Information necessary to convert an Iterable into a Calcite Cursor
message CursorFactory {
  enum Style {
    OBJECT = 0;
    RECORD = 1;
    RECORD_PROJECTION = 2;
    ARRAY = 3;
    LIST = 4;
    MAP = 5;
  }

  Style style = 1;
  string class_name = 2;
  repeated string field_names = 3;
}

// Has to be consistent with Meta.StatementType
enum StatementType {
  SELECT = 0;
  INSERT = 1;
  UPDATE = 2;
  DELETE = 3;
  UPSERT = 4;
  MERGE = 5;
  OTHER_DML = 6;
  CREATE = 7;
  DROP = 8;
  ALTER = 9;
  OTHER_DDL = 10;
  CALL = 11;
}

// Base class for a column type
message AvaticaType {
  uint32 id = 1;
  string name = 2;
  Rep rep = 3;

  repeated ColumnMetaData columns = 4; // Only present when name = STRUCT
  AvaticaType component = 5; // Only present when name = ARRAY
}

// Generic wrapper to support any SQL type. Struct-like to work around no polymorphism construct.
message TypedValue {
  Rep type = 1; // The actual type that was serialized in the general attribute below

  bool bool_value = 2; // boolean
  string string_value = 3; // char/varchar
  sint64 number_value = 4; // var-len encoding lets us shove anything from byte to long
                           // includes numeric types and date/time types.
  bytes bytes_value = 5; // binary/varbinary
  double double_value = 6; // big numbers
  bool null = 7; // a null object

  repeated TypedValue array_value = 8; // The Array
  Rep component_type = 9; // If an Array, the representation for the array values

  bool implicitly_null = 10; // Differentiate between explicitly null (user-set) and implicitly null
                            // (un-set by the user)
}

enum Rep {
  PRIMITIVE_BOOLEAN = 0;
  PRIMITIVE_BYTE = 1;
  PRIMITIVE_CHAR = 2;
  PRIMITIVE_SHORT = 3;
  PRIMITIVE_INT = 4;
  PRIMITIVE_LONG = 5;
  PRIMITIVE_FLOAT = 6;
  PRIMITIVE_DOUBLE = 7;
  BOOLEAN = 8;
  BYTE = 9;
  CHARACTER = 10;
  SHORT = 11;
  INTEGER = 12;
  LONG = 13;
  FLOAT = 14;
  DOUBLE = 15;
  BIG_INTEGER = 25;
  BIG_DECIMAL = 26;
  JAVA_SQL_TIME = 16;
  JAVA_SQL_TIMESTAMP = 17;
  JAVA_SQL_DATE = 18;
  JAVA_UTIL_DATE = 19;
  BYTE_STRING = 20;
  STRING = 21;
  NUMBER = 22;
  OBJECT = 23;
  NULL = 24;
  ARRAY = 27;
  STRUCT = 28;
  MULTISET = 29;
}

message RpcMetadata {
  string server_address = 1;
}

// Message which encapsulates another message to support a single RPC endpoint
message WireMessage {
  string name = 1;
  bytes wrapped_message = 2;
}
