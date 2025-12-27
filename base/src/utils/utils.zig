pub const strings = @import("strings.zig");
pub const buffer = @import("buffer.zig");

pub const isDigit = strings.isDigit;
pub const isAlpha = strings.isAlpha;
pub const isAlphaNumeric = strings.isAlphaNumeric;
pub const isUpperCase = strings.isUpperCase;
pub const isLowerCase = strings.isLowerCase;
pub const isWhitespace = strings.isWhitespace;
pub const trimWhitespace = strings.trimWhitespace;
pub const escape = strings.escape;
pub const escapeHtml = strings.escapeHtml;
pub const hash = strings.hash;
pub const generateId = strings.generateId;

pub const WriteBuffer = buffer.WriteBuffer;
pub const MultiBuffer = buffer.MultiBuffer;
