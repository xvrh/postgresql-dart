import 'dart:convert';
import 'dart:typed_data';

import 'package:buffer/buffer.dart';

import '../buffer.dart';
import '../types.dart';
import 'type_registry.dart';

final _bool0 = Uint8List(1)..[0] = 0;
final _bool1 = Uint8List(1)..[0] = 1;
final _dashUnit = '-'.codeUnits.first;
final _hex = <String>[
  '0',
  '1',
  '2',
  '3',
  '4',
  '5',
  '6',
  '7',
  '8',
  '9',
  'a',
  'b',
  'c',
  'd',
  'e',
  'f',
];
final _numericRegExp = RegExp(r'^(\d*)(\.\d*)?$');
final _leadingZerosRegExp = RegExp('^0+');
final _trailingZerosRegExp = RegExp(r'0+$');

// The Dart SDK provides an optimized implementation for JSON from and to UTF-8
// that doesn't allocate intermediate strings.
final _jsonUtf8Codec = json.fuse(utf8);

Codec<Object?, List<int>> _jsonFusedEncoding(Encoding encoding) {
  if (encoding == utf8) {
    return _jsonUtf8Codec;
  } else {
    return json.fuse(encoding);
  }
}

class PostgresBinaryEncoder {
  final int _typeOid;

  const PostgresBinaryEncoder(this._typeOid);

  Uint8List convert(Object input, Encoding encoding) {
    switch (_typeOid) {
      case TypeOid.voidType:
        throw ArgumentError('Cannot encode `$input` into oid($_typeOid).');
      case TypeOid.boolean:
        {
          if (input is bool) {
            return input ? _bool1 : _bool0;
          }
          throw FormatException(
              'Invalid type for parameter value. Expected: bool Got: ${input.runtimeType}');
        }
      case TypeOid.bigInteger:
        {
          if (input is int) {
            final bd = ByteData(8);
            bd.setInt64(0, input);
            return bd.buffer.asUint8List();
          }
          throw FormatException(
              'Invalid type for parameter value. Expected: int Got: ${input.runtimeType}');
        }
      case TypeOid.integer:
        {
          if (input is int) {
            final bd = ByteData(4);
            bd.setInt32(0, input);
            return bd.buffer.asUint8List();
          }
          throw FormatException(
              'Invalid type for parameter value. Expected: int Got: ${input.runtimeType}');
        }
      case TypeOid.smallInteger:
        {
          if (input is int) {
            final bd = ByteData(2);
            bd.setInt16(0, input);
            return bd.buffer.asUint8List();
          }
          throw FormatException(
              'Invalid type for parameter value. Expected: int Got: ${input.runtimeType}');
        }
      case TypeOid.name:
      case TypeOid.text:
      case TypeOid.varChar:
        {
          if (input is String) {
            return castBytes(encoding.encode(input));
          }
          throw FormatException(
              'Invalid type for parameter value. Expected: String Got: ${input.runtimeType}');
        }
      case TypeOid.real:
        {
          if (input is double) {
            final bd = ByteData(4);
            bd.setFloat32(0, input);
            return bd.buffer.asUint8List();
          }
          throw FormatException(
              'Invalid type for parameter value. Expected: double Got: ${input.runtimeType}');
        }
      case TypeOid.double:
        {
          if (input is double) {
            final bd = ByteData(8);
            bd.setFloat64(0, input);
            return bd.buffer.asUint8List();
          }
          throw FormatException(
              'Invalid type for parameter value. Expected: double Got: ${input.runtimeType}');
        }
      case TypeOid.date:
        {
          if (input is DateTime) {
            final bd = ByteData(4);
            bd.setInt32(0, input.toUtc().difference(DateTime.utc(2000)).inDays);
            return bd.buffer.asUint8List();
          }
          throw FormatException(
              'Invalid type for parameter value. Expected: DateTime Got: ${input.runtimeType}');
        }

      case TypeOid.timestampWithoutTimezone:
        {
          if (input is DateTime) {
            final bd = ByteData(8);
            final diff = input.toUtc().difference(DateTime.utc(2000));
            bd.setInt64(0, diff.inMicroseconds);
            return bd.buffer.asUint8List();
          }
          throw FormatException(
              'Invalid type for parameter value. Expected: DateTime Got: ${input.runtimeType}');
        }

      case TypeOid.timestampWithTimezone:
        {
          if (input is DateTime) {
            final bd = ByteData(8);
            bd.setInt64(
                0, input.toUtc().difference(DateTime.utc(2000)).inMicroseconds);
            return bd.buffer.asUint8List();
          }
          throw FormatException(
              'Invalid type for parameter value. Expected: DateTime Got: ${input.runtimeType}');
        }

      case TypeOid.interval:
        {
          if (input is Interval) {
            final bd = ByteData(16);
            bd.setInt64(0, input.microseconds);
            bd.setInt32(8, input.days);
            bd.setInt32(12, input.months);
            return bd.buffer.asUint8List();
          }
          if (input is Duration) {
            final bd = ByteData(16);
            bd.setInt64(0, input.inMicroseconds);
            // ignoring the second 8 bytes
            return bd.buffer.asUint8List();
          }
          throw FormatException(
              'Invalid type for parameter value. Expected: Interval Got: ${input.runtimeType}');
        }

      case TypeOid.numeric:
        {
          Object source = input;

          if (source is double || source is int) {
            source = input.toString();
          }
          if (source is String) {
            return _encodeNumeric(source, encoding);
          }
          throw FormatException(
              'Invalid type for parameter value. Expected: String|double|int Got: ${input.runtimeType}');
        }

      case TypeOid.jsonb:
        {
          final jsonBytes = _jsonFusedEncoding(encoding).encode(input);
          final writer = PgByteDataWriter(
              bufferLength: jsonBytes.length + 1, encoding: encoding);
          writer.writeUint8(1);
          writer.write(jsonBytes);
          return writer.toBytes();
        }

      case TypeOid.json:
        return castBytes(_jsonFusedEncoding(encoding).encode(input));

      case TypeOid.byteArray:
        {
          if (input is List<int>) {
            return castBytes(input);
          }
          throw FormatException(
              'Invalid type for parameter value. Expected: List<int> Got: ${input.runtimeType}');
        }

      case TypeOid.uuid:
        {
          if (input is! String) {
            throw FormatException(
                'Invalid type for parameter value. Expected: String Got: ${input.runtimeType}');
          }

          final hexBytes = input
              .toLowerCase()
              .codeUnits
              .where((c) => c != _dashUnit)
              .toList();
          if (hexBytes.length != 32) {
            throw FormatException(
                "Invalid UUID string. There must be exactly 32 hexadecimal (0-9 and a-f) characters and any number of '-' characters.");
          }

          int byteConvert(int charCode) {
            if (charCode >= 48 && charCode <= 57) {
              return charCode - 48;
            } else if (charCode >= 97 && charCode <= 102) {
              return charCode - 87;
            }

            throw FormatException(
                'Invalid UUID string. Contains non-hexadecimal character (0-9 and a-f).');
          }

          final outBuffer = Uint8List(16);
          for (var i = 0, j = 0; i < hexBytes.length; i += 2, j++) {
            final upperByte = byteConvert(hexBytes[i]);
            final lowerByte = byteConvert(hexBytes[i + 1]);

            outBuffer[j] = (upperByte << 4) + lowerByte;
          }
          return outBuffer;
        }

      case TypeOid.point:
        {
          if (input is Point) {
            final bd = ByteData(16);
            bd.setFloat64(0, input.latitude);
            bd.setFloat64(8, input.longitude);
            return bd.buffer.asUint8List();
          }
          throw FormatException(
              'Invalid type for parameter value. Expected: PgPoint Got: ${input.runtimeType}');
        }
      case TypeOid.regtype:
        final oid = input is Type ? input.oid : null;
        if (oid == null) {
          throw FormatException(
              'Invalid type for parameter value, expected a data type an oid, got $input');
        }

        final outBuffer = Uint8List(4);
        outBuffer.buffer.asByteData().setInt32(0, oid);
        return outBuffer;
      case TypeOid.booleanArray:
        {
          if (input is List) {
            return _writeListBytes<bool>(
              _castOrThrowList<bool>(input),
              16,
              (_) => 1,
              (writer, item) => writer.writeUint8(item ? 1 : 0),
              encoding,
            );
          }
          throw FormatException(
              'Invalid type for parameter value. Expected: List<bool> Got: ${input.runtimeType}');
        }

      case TypeOid.integerArray:
        {
          if (input is List) {
            return _writeListBytes<int>(
              _castOrThrowList<int>(input),
              23,
              (_) => 4,
              (writer, item) => writer.writeInt32(item),
              encoding,
            );
          }
          throw FormatException(
              'Invalid type for parameter value. Expected: List<int> Got: ${input.runtimeType}');
        }

      case TypeOid.bigIntegerArray:
        {
          if (input is List) {
            return _writeListBytes<int>(
              _castOrThrowList<int>(input),
              20,
              (_) => 8,
              (writer, item) => writer.writeInt64(item),
              encoding,
            );
          }
          throw FormatException(
              'Invalid type for parameter value. Expected: List<int> Got: ${input.runtimeType}');
        }

      case TypeOid.varCharArray:
        {
          if (input is List) {
            final bytesArray =
                _castOrThrowList<String>(input).map((v) => encoding.encode(v));
            return _writeListBytes<List<int>>(
              bytesArray,
              1043,
              (item) => item.length,
              (writer, item) => writer.write(item),
              encoding,
            );
          }
          throw FormatException(
              'Invalid type for parameter value. Expected: List<String> Got: ${input.runtimeType}');
        }

      case TypeOid.textArray:
        {
          if (input is List) {
            final bytesArray =
                _castOrThrowList<String>(input).map((v) => encoding.encode(v));
            return _writeListBytes<List<int>>(
              bytesArray,
              25,
              (item) => item.length,
              (writer, item) => writer.write(item),
              encoding,
            );
          }
          throw FormatException(
              'Invalid type for parameter value. Expected: List<String> Got: ${input.runtimeType}');
        }

      case TypeOid.doubleArray:
        {
          if (input is List) {
            return _writeListBytes<double>(
              _castOrThrowList<double>(input),
              701,
              (_) => 8,
              (writer, item) => writer.writeFloat64(item),
              encoding,
            );
          }
          throw FormatException(
              'Invalid type for parameter value. Expected: List<double> Got: ${input.runtimeType}');
        }

      case TypeOid.jsonbArray:
        {
          if (input is List) {
            final objectsArray = input.map(_jsonFusedEncoding(encoding).encode);
            return _writeListBytes<List<int>>(
              objectsArray,
              3802,
              (item) => item.length + 1,
              (writer, item) {
                writer.writeUint8(1);
                writer.write(item);
              },
              encoding,
            );
          }
          throw FormatException(
              'Invalid type for parameter value. Expected: List Got: ${input.runtimeType}');
        }
    }
    // Pass-through of Uint8List instances allows client with custom types to
    // encode their types for efficient binary transport.
    if (input is Uint8List) {
      return input;
    }
    throw ArgumentError('Cannot encode `$input` into oid($_typeOid).');
  }

  List<V> _castOrThrowList<V>(List input) {
    if (input is List<V>) {
      return input;
    }
    if (input.any((e) => e is! V)) {
      throw FormatException(
          'Invalid type for parameter value. Expected: List<${V.runtimeType}> Got: ${input.runtimeType}');
    }
    return input.cast<V>();
  }

  Uint8List _writeListBytes<V>(
    Iterable<V> value,
    int type,
    int Function(V item) lengthEncoder,
    void Function(PgByteDataWriter writer, V item) valueEncoder,
    Encoding encoding,
  ) {
    final writer = PgByteDataWriter(encoding: encoding);

    writer.writeInt32(1); // dimension
    writer.writeInt32(0); // ign
    writer.writeInt32(type); // type
    writer.writeInt32(value.length); // size
    writer.writeInt32(1); // index

    for (final i in value) {
      final len = lengthEncoder(i);
      writer.writeInt32(len);
      valueEncoder(writer, i);
    }

    return writer.toBytes();
  }

  /// Encode String / double / int to numeric / decimal  without loosing precision.
  /// Compare implementation: https://github.com/frohoff/jdk8u-dev-jdk/blob/da0da73ab82ed714dc5be94acd2f0d00fbdfe2e9/src/share/classes/java/math/BigDecimal.java#L409
  Uint8List _encodeNumeric(String value, Encoding encoding) {
    value = value.trim();
    var signByte = 0x0000;
    if (value.toLowerCase() == 'nan') {
      signByte = 0xc000;
      value = '';
    } else if (value.startsWith('-')) {
      value = value.substring(1);
      signByte = 0x4000;
    } else if (value.startsWith('+')) {
      value = value.substring(1);
    }
    if (!_numericRegExp.hasMatch(value)) {
      throw FormatException(
          'Invalid format for parameter value. Expected: String which matches "/^(\\d*)(\\.\\d*)?\$/" Got: $value');
    }
    final parts = value.split('.');

    var intPart = parts[0].replaceAll(_leadingZerosRegExp, '');
    var intWeight = intPart.isEmpty ? -1 : (intPart.length - 1) ~/ 4;
    intPart = intPart.padLeft((intWeight + 1) * 4, '0');

    var fractPart = parts.length > 1 ? parts[1] : '';
    final dScale = fractPart.length;
    fractPart = fractPart.replaceAll(_trailingZerosRegExp, '');
    var fractWeight = fractPart.isEmpty ? -1 : (fractPart.length - 1) ~/ 4;
    fractPart = fractPart.padRight((fractWeight + 1) * 4, '0');

    var weight = intWeight;
    if (intWeight < 0) {
      // If int part has no weight, handle leading zeros in fractional part.
      if (fractPart.isEmpty) {
        // Weight of value 0 or '' is 0;
        weight = 0;
      } else {
        final leadingZeros =
            _leadingZerosRegExp.firstMatch(fractPart)?.group(0);
        if (leadingZeros != null) {
          final leadingZerosWeight =
              leadingZeros.length ~/ 4; // Get count of leading zeros '0000'
          fractPart = fractPart
              .substring(leadingZerosWeight * 4); // Remove leading zeros '0000'
          fractWeight -= leadingZerosWeight;
          weight = -(leadingZerosWeight + 1); // Ignore leading zeros in weight
        }
      }
    } else if (fractWeight < 0) {
      // If int fract has no weight, handle trailing zeros in int part.
      final trailingZeros = _trailingZerosRegExp.firstMatch(intPart)?.group(0);
      if (trailingZeros != null) {
        final trailingZerosWeight =
            trailingZeros.length ~/ 4; // Get count of trailing zeros '0000'
        intPart = intPart.substring(
            0,
            intPart.length -
                trailingZerosWeight * 4); // Remove leading zeros '0000'
        intWeight -= trailingZerosWeight;
      }
    }

    final nDigits = intWeight + fractWeight + 2;

    final writer = PgByteDataWriter(encoding: encoding);
    writer.writeInt16(nDigits);
    writer.writeInt16(weight);
    writer.writeUint16(signByte);
    writer.writeInt16(dScale);
    for (var i = 0; i <= intWeight * 4; i += 4) {
      writer.writeInt16(int.parse(intPart.substring(i, i + 4)));
    }
    for (var i = 0; i <= fractWeight * 4; i += 4) {
      writer.writeInt16(int.parse(fractPart.substring(i, i + 4)));
    }
    return writer.toBytes();
  }
}

class PostgresBinaryDecoder {
  final int typeOid;

  PostgresBinaryDecoder(this.typeOid);

  Object? convert(Uint8List input, Encoding encoding) {
    late final buffer =
        ByteData.view(input.buffer, input.offsetInBytes, input.lengthInBytes);

    switch (typeOid) {
      case TypeOid.name:
      case TypeOid.text:
      case TypeOid.varChar:
        return encoding.decode(input);
      case TypeOid.boolean:
        return (buffer.getInt8(0) != 0);
      case TypeOid.smallInteger:
        return buffer.getInt16(0);
      case TypeOid.integer:
        return buffer.getInt32(0);
      case TypeOid.bigInteger:
        return buffer.getInt64(0);
      case TypeOid.real:
        return buffer.getFloat32(0);
      case TypeOid.double:
        return buffer.getFloat64(0);
      case TypeOid.timestampWithoutTimezone:
      case TypeOid.timestampWithTimezone:
        return DateTime.utc(2000)
            .add(Duration(microseconds: buffer.getInt64(0)));

      case TypeOid.interval:
        return Interval(
          microseconds: buffer.getInt64(0),
          days: buffer.getInt32(8),
          months: buffer.getInt32(12),
        );

      case TypeOid.numeric:
        return _decodeNumeric(input);

      case TypeOid.date:
        return DateTime.utc(2000).add(Duration(days: buffer.getInt32(0)));

      case TypeOid.jsonb:
        {
          // Removes version which is first character and currently always '1'
          final bytes = input.buffer
              .asUint8List(input.offsetInBytes + 1, input.lengthInBytes - 1);
          return _jsonFusedEncoding(encoding).decode(bytes);
        }

      case TypeOid.json:
        return _jsonFusedEncoding(encoding).decode(input);

      case TypeOid.byteArray:
        return input;

      case TypeOid.uuid:
        {
          final buf = StringBuffer();
          for (var i = 0; i < buffer.lengthInBytes; i++) {
            final byteValue = buffer.getUint8(i);
            final upperByteValue = byteValue >> 4;
            final lowerByteValue = byteValue & 0x0f;

            final upperByteHex = _hex[upperByteValue];
            final lowerByteHex = _hex[lowerByteValue];
            buf.write(upperByteHex);
            buf.write(lowerByteHex);
            if (i == 3 || i == 5 || i == 7 || i == 9) {
              buf.writeCharCode(_dashUnit);
            }
          }

          return buf.toString();
        }
      case TypeOid.regtype:
        final data = input.buffer.asByteData(input.offsetInBytes, input.length);
        final oid = data.getInt32(0);
        return TypeRegistry.instance.resolveOid(oid);
      case TypeOid.voidType:
        return null;

      case TypeOid.point:
        return Point(buffer.getFloat64(0), buffer.getFloat64(8));

      case TypeOid.booleanArray:
        return readListBytes<bool>(
            input, (reader, _) => reader.readUint8() != 0);

      case TypeOid.integerArray:
        return readListBytes<int>(input, (reader, _) => reader.readInt32());
      case TypeOid.bigIntegerArray:
        return readListBytes<int>(input, (reader, _) => reader.readInt64());

      case TypeOid.varCharArray:
      case TypeOid.textArray:
        return readListBytes<String>(input, (reader, length) {
          return encoding.decode(length > 0 ? reader.read(length) : []);
        });

      case TypeOid.doubleArray:
        return readListBytes<double>(
            input, (reader, _) => reader.readFloat64());

      case TypeOid.jsonbArray:
        return readListBytes<dynamic>(input, (reader, length) {
          reader.read(1);
          final bytes = reader.read(length - 1);
          return _jsonFusedEncoding(encoding).decode(bytes);
        });
    }
    return TypedBytes(typeOid: typeOid, bytes: input);
  }

  List<V> readListBytes<V>(Uint8List data,
      V Function(ByteDataReader reader, int length) valueDecoder) {
    if (data.length < 16) {
      return [];
    }

    final reader = ByteDataReader()..add(data);
    reader.read(12); // header

    final decoded = [].cast<V>();
    final size = reader.readInt32();

    reader.read(4); // index

    for (var i = 0; i < size; i++) {
      final len = reader.readInt32();
      decoded.add(valueDecoder(reader, len));
    }

    return decoded;
  }

  /// Decode numeric / decimal to String without loosing precision.
  /// See encoding: https://github.com/postgres/postgres/blob/0e39a608ed5545cc6b9d538ac937c3c1ee8cdc36/src/backend/utils/adt/numeric.c#L305
  /// See implementation: https://github.com/charmander/pg-numeric/blob/0c310eeb11dc680dffb7747821e61d542831108b/index.js#L13
  static String _decodeNumeric(Uint8List value) {
    final reader = ByteDataReader()..add(value);
    final nDigits =
        reader.readInt16(); // non-zero digits, data buffer length = 2 * nDigits
    var weight = reader.readInt16(); // weight of first digit
    final signByte =
        reader.readUint16(); // NUMERIC_POS, NEG, NAN, PINF, or NINF
    final dScale = reader.readInt16(); // display scale
    if (signByte == 0xc000) return 'NaN';
    final sign = signByte == 0x4000 ? '-' : '';
    var intPart = '';
    var fractPart = '';

    final fractOmitted = -(weight + 1);
    if (fractOmitted > 0) {
      // If value < 0, the leading zeros in fractional part were omitted.
      fractPart += '0000' * fractOmitted;
    }

    for (var i = 0; i < nDigits; i++) {
      if (weight >= 0) {
        intPart += reader.readInt16().toString().padLeft(4, '0');
      } else {
        fractPart += reader.readInt16().toString().padLeft(4, '0');
      }
      weight--;
    }

    if (weight >= 0) {
      // Trailing zeros were omitted
      intPart += '0000' * (weight + 1);
    }

    var result = '$sign${intPart.replaceAll(_leadingZerosRegExp, '')}';
    if (result.isEmpty) {
      result = '0'; // Show at least 0, if no int value is given.
    }
    if (dScale > 0) {
      // Only add fractional digits, if dScale allows
      result += '.${fractPart.padRight(dScale, '0').substring(0, dScale)}';
    }
    return result;
  }
}