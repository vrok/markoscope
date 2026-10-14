// Protocol Buffers (proto2, proto3, editions) and gRPC service definitions for highlight.js,
// used for ```proto, ```protobuf, ```proto3 and ```grpc code blocks.
hljs.registerLanguage('protobuf', hljs => {
  const IDENT = /[A-Za-z_][A-Za-z0-9_]*/;
  const OPTION_NAME = /\(\s*\.?[A-Za-z_][\w.]*\s*\)/;
  return {
    name: 'Protocol Buffers',
    aliases: ['proto', 'proto2', 'proto3', 'grpc'],
    keywords: {
      keyword: [
        'syntax', 'edition', 'package', 'import', 'public', 'weak', 'option',
        'optional', 'required', 'repeated', 'oneof', 'map', 'reserved', 'extensions', 'to', 'max',
        'message', 'enum', 'service', 'extend', 'group', 'rpc', 'returns', 'stream',
      ],
      type: [
        'double', 'float', 'int32', 'int64', 'uint32', 'uint64', 'sint32', 'sint64',
        'fixed32', 'fixed64', 'sfixed32', 'sfixed64', 'bool', 'string', 'bytes',
      ],
      literal: ['true', 'false', 'inf', 'nan'],
    },
    contains: [
      hljs.QUOTE_STRING_MODE,
      hljs.APOS_STRING_MODE,
      hljs.C_LINE_COMMENT_MODE,
      hljs.C_BLOCK_COMMENT_MODE,
      hljs.C_NUMBER_MODE,
      // message Foo { / enum Status { / service Greeter { / extend Bar {
      { match: [/\b(?:message|enum|service|extend)\s+/, IDENT], scope: { 1: 'keyword', 2: 'title.class' } },
      // rpc SayHello(
      { match: [/\brpc\s+/, IDENT], scope: { 1: 'keyword', 2: 'title.function' } },
      // Custom options: option (google.api.http) = ...; and [(validate.rules).string.min_len = 1]
      { match: [/\boption\s+/, OPTION_NAME], scope: { 1: 'keyword', 2: 'meta' } },
      { match: [/[[,]\s*/, OPTION_NAME], scope: { 2: 'meta' } },
      // Qualified types: google.protobuf.Timestamp
      { scope: 'type', match: /\b(?:[a-z_]\w*\.)+[A-Z]\w*/ },
      // Enum values: STATUS_ACTIVE = 1;
      { scope: 'variable.constant', match: /\b[A-Z][A-Z0-9_]*(?=\s*=)/ },
      // Message types in fields and rpc signatures: HelloRequest, Status
      { scope: 'type', match: /\b[A-Z][A-Za-z0-9_]*[a-z][A-Za-z0-9_]*\b/ },
    ],
  };
});
