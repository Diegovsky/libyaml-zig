pub const ParserError = error{ ParserInit, AlreadySet, ReadingFailed, ParsingError, InternalError, OutOfMemory, TypeError };
pub const LoaderError = error{Validation};
pub const YamlError = LoaderError || ParserError;
