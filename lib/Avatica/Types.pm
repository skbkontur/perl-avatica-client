package Avatica::Types;

use strict;
use warnings;
use Carp 'croak';
use Time::Piece;
use Scalar::Util qw/looks_like_number/;

use Avatica::Client;

#
# JAVA Types https://github.com/JetBrains/jdk8u_jdk/blob/master/src/share/classes/java/sql/Types.java
#

use constant JAVA_TO_REP => {
    -6  => Avatica::Client::Protocol::Rep::BYTE(),              # TINYINT
    5   => Avatica::Client::Protocol::Rep::SHORT(),             # SMALLINT
    4   => Avatica::Client::Protocol::Rep::INTEGER(),           # INTEGER
    -5  => Avatica::Client::Protocol::Rep::LONG(),              # BIGINT
    6   => Avatica::Client::Protocol::Rep::DOUBLE(),            # FLOAT
    8   => Avatica::Client::Protocol::Rep::DOUBLE(),            # DOUBLE
    2   => Avatica::Client::Protocol::Rep::BIG_DECIMAL(),       # NUMERIC
    1   => Avatica::Client::Protocol::Rep::STRING(),            # CHAR
    91  => Avatica::Client::Protocol::Rep::JAVA_SQL_DATE(),     # DATE
    92  => Avatica::Client::Protocol::Rep::JAVA_SQL_TIME(),     # TIME
    93  => Avatica::Client::Protocol::Rep::JAVA_SQL_TIMESTAMP(),    # TIMESTAMP
    -2  => Avatica::Client::Protocol::Rep::BYTE_STRING(),       # BINARY
    -3  => Avatica::Client::Protocol::Rep::BYTE_STRING(),       # VARBINARY
    16  => Avatica::Client::Protocol::Rep::BOOLEAN(),           # BOOLEAN

    # These are the Non-standard types defined by Phoenix
    18  => Avatica::Client::Protocol::Rep::JAVA_SQL_TIME(),     # UNSIGNED_TIME
    19  => Avatica::Client::Protocol::Rep::JAVA_SQL_DATE(),     # UNSIGNED_DATE
    15  => Avatica::Client::Protocol::Rep::DOUBLE(),            # UNSIGNED_DOUBLE
    14  => Avatica::Client::Protocol::Rep::DOUBLE(),            # UNSIGNED_FLOAT
    9   => Avatica::Client::Protocol::Rep::INTEGER(),           # UNSIGNED_INT
    10  => Avatica::Client::Protocol::Rep::LONG(),              # UNSIGNED_LONG
    13  => Avatica::Client::Protocol::Rep::SHORT(),             # UNSIGNED_SMALLINT
    20  => Avatica::Client::Protocol::Rep::JAVA_SQL_TIMESTAMP(),    # UNSIGNED_TIMESTAMP
    11  => Avatica::Client::Protocol::Rep::BYTE(),              # UNSIGNED_TINYINT

    # The following are not used by Phoenix, but some of these are used by Avatica for
    # parameter types
    -7  => Avatica::Client::Protocol::Rep::BOOLEAN(),           # BIT
    7   => Avatica::Client::Protocol::Rep::DOUBLE(),            # REAL
    3   => Avatica::Client::Protocol::Rep::BIG_DECIMAL(),       # DECIMAL
    12  => Avatica::Client::Protocol::Rep::STRING(),            # VARCHAR
    -1  => Avatica::Client::Protocol::Rep::STRING(),            # LONGVARCHAR
    -4  => Avatica::Client::Protocol::Rep::BYTE_STRING(),       # LONGVARBINARY
    2004  => Avatica::Client::Protocol::Rep::BYTE_STRING(),     # BLOB
    2005  => Avatica::Client::Protocol::Rep::STRING(),          # CLOB
    -15 => Avatica::Client::Protocol::Rep::STRING(),            # NCHAR
    -9  => Avatica::Client::Protocol::Rep::STRING(),            # NVARCHAR
    -16 => Avatica::Client::Protocol::Rep::STRING(),            # LONGNVARCHAR
    2011  => Avatica::Client::Protocol::Rep::STRING(),          # NCLOB
    2009  => Avatica::Client::Protocol::Rep::STRING(),          # SQLXML
    2013 => Avatica::Client::Protocol::Rep::JAVA_SQL_TIME(),    # TIME_WITH_TIMEZONE
    2014 => Avatica::Client::Protocol::Rep::JAVA_SQL_TIMESTAMP(),    # TIMESTAMP_WITH_TIMEZONE

    # Returned by Avatica for Arrays in EMPTY resultsets
    2000  => Avatica::Client::Protocol::Rep::BYTE_STRING(),     # JAVA_OBJECT
};

use constant REP_TO_TYPE_VALUE => {
    Avatica::Client::Protocol::Rep::INTEGER()            => 'number_value',
    Avatica::Client::Protocol::Rep::PRIMITIVE_INT()      => 'number_value',
    Avatica::Client::Protocol::Rep::SHORT()              => 'number_value',
    Avatica::Client::Protocol::Rep::PRIMITIVE_SHORT()    => 'number_value',
    Avatica::Client::Protocol::Rep::LONG()               => 'number_value',
    Avatica::Client::Protocol::Rep::PRIMITIVE_LONG()     => 'number_value',
    Avatica::Client::Protocol::Rep::BYTE()               => 'number_value',
    Avatica::Client::Protocol::Rep::JAVA_SQL_TIME()      => 'number_value',
    Avatica::Client::Protocol::Rep::JAVA_SQL_DATE()      => 'number_value',
    Avatica::Client::Protocol::Rep::JAVA_SQL_TIMESTAMP() => 'number_value',

    Avatica::Client::Protocol::Rep::BYTE_STRING()        => 'bytes_value',

    Avatica::Client::Protocol::Rep::DOUBLE()             => 'double_value',
    Avatica::Client::Protocol::Rep::PRIMITIVE_DOUBLE()   => 'double_value',

    Avatica::Client::Protocol::Rep::PRIMITIVE_CHAR()     => 'string_value',
    Avatica::Client::Protocol::Rep::CHARACTER()          => 'string_value',
    Avatica::Client::Protocol::Rep::BIG_DECIMAL()        => 'string_value',
    Avatica::Client::Protocol::Rep::STRING()             => 'string_value',

    Avatica::Client::Protocol::Rep::BOOLEAN()            => 'bool_value',
    Avatica::Client::Protocol::Rep::PRIMITIVE_BOOLEAN()  => 'bool_value',
};

# params:
# class
# [Avatica::Client::Protocol::ColumnValue, ...]
# [Avatica::Client::Protocol::ColumnMetaData, ...]
sub row_from_jdbc {
    my ($class, $columns_values, $columns_meta) = @_;
    croak 'The number of arguments is not the same as the expected number' if $#{$columns_values} != $#{$columns_meta};
    return [
        map {
            $class->from_jdbc($columns_values->[$_], $columns_meta->[$_])
        }
        0 .. $#{$columns_meta}
    ];
}

# params:
# class
# Avatica::Client::Protocol::ColumnValue
# Avatica::Client::Protocol::ColumnMetaData
sub from_jdbc {
    my ($class, $column_value, $column_meta) = @_;

    my $scalar_value = $column_value->get_scalar_value;

    return undef if $scalar_value && $scalar_value->get_null;

    if ($column_value->get_has_array_value) {
        my $jdbc_type_id = $column_meta->get_type->get_component->get_id;
        my $rep = $class->convert_jdbc_to_rep_type($jdbc_type_id);

        my $type = $class->REP_TO_TYPE_VALUE()->{$rep};
        my $method = "get_$type";

        my $values = [];
        for my $v (@{$column_value->get_array_value_list}) {
            my $res = $v->$method();
            push @$values, $class->convert_from_jdbc($res, $rep);
        }

        return $values;
    }

    my $jdbc_type_id = $column_meta->get_type->get_id;
    my $rep = $class->convert_jdbc_to_rep_type($jdbc_type_id);

    my $type = $class->REP_TO_TYPE_VALUE()->{$rep};
    my $method = "get_$type";

    my $res = $scalar_value->$method();

    return $class->convert_from_jdbc($res, $rep);
}

# params:
# class
# values
# [Avatica::Client::Protocol::AvaticaParameter, ...]
sub row_to_jdbc {
    my ($class, $values, $avatica_params) = @_;
    croak 'The number of arguments is not the same as the expected number' if $#{$values} != $#{$avatica_params};
    return [
        map {
            $class->to_jdbc($values->[$_], $avatica_params->[$_])
        }
        0 .. $#{$avatica_params}
    ];
}

# params:
# class
# value
# Avatica::Client::Protocol::AvaticaParameter
sub to_jdbc {
    my ($class, $value, $avatica_param) = @_;

    my $jdbc_type_id = $avatica_param->get_parameter_type;

    my $typed_value = Avatica::Client::Protocol::TypedValue->new;

    unless (defined $value) {
        $typed_value->set_null(1);
        $typed_value->set_type(Avatica::Client::Protocol::Rep::NULL());
        return $typed_value;
    }

    $typed_value->set_null(0);

    # Phoenix add base 3000 for array types
    # https://github.com/apache/phoenix/blob/2a2d9964d29c2e47667114dbc3ca43c0e264a221/phoenix-core/src/main/java/org/apache/phoenix/schema/types/PDataType.java#L518
    my $is_array = $jdbc_type_id > 2900 && $jdbc_type_id < 3100;

    # Phoenix specific
    if ($is_array) {
        my $element_rep = $class->convert_jdbc_to_rep_type($jdbc_type_id - 3000);
        my $type = $class->REP_TO_TYPE_VALUE->{$element_rep};
        my $method = "set_$type";

        $typed_value->set_type(Avatica::Client::Protocol::Rep::ARRAY());
        $typed_value->set_component_type($element_rep);

        for my $v (@$value) {
            my $tv = Avatica::Client::Protocol::TypedValue->new;
            unless (defined $v) {
                $tv->set_null(1);
                $tv->set_type(Avatica::Client::Protocol::Rep::NULL());
                $typed_value->add_array_value($tv);
                next;
            }
            $tv->set_type($element_rep);
            $tv->$method($class->convert_to_jdbc($v, $element_rep));
            $typed_value->add_array_value($tv);
        }
        return $typed_value;
    }

    my $rep = $class->convert_jdbc_to_rep_type($jdbc_type_id);
    my $type = $class->REP_TO_TYPE_VALUE->{$rep};
    my $method = "set_$type";

    $typed_value->set_type($rep);
    $typed_value->$method($class->convert_to_jdbc($value, $rep));

    return $typed_value;
}

sub convert_from_jdbc {
    my ($class, $value, $rep) = @_;

    if ($rep == Avatica::Client::Protocol::Rep::JAVA_SQL_TIME()) {
        my $sec = int($value / 1000);
        my $milli = $value % 1000;
        my $time = Time::Piece->strptime($sec, '%s')->time;
        $time .= '.' . $milli if $milli;
        return $time;
    }

    if ($rep == Avatica::Client::Protocol::Rep::JAVA_SQL_DATE()) {
        return Time::Piece->strptime($value * 86400, '%s')->ymd;
    }

    if ($rep == Avatica::Client::Protocol::Rep::JAVA_SQL_TIMESTAMP()) {
        my $sec = int($value / 1000);
        my $milli = $value % 1000;
        my $datetime = Time::Piece->strptime($sec, '%s')->strftime('%Y-%m-%d %H:%M:%S');
        $datetime .= '.' . $milli if $milli;
        return $datetime;
    }

    return $value;
}

sub convert_to_jdbc {
    my ($class, $value, $rep) = @_;

    if ($rep == Avatica::Client::Protocol::Rep::JAVA_SQL_TIME()) {
        return $value if looks_like_number($value);

        my ($datetime, $milli) = split /\./, $value;
        my ($date, $time) = split /[tT ]/, $datetime;
        $time = $date unless $time;

        my ($h, $m, $s) = split /:/, $time;
        return ((($h // 0) * 60 + ($m // 0)) * 60 + ($s // 0)) * 1000 + ($milli ? substr($milli . '00', 0, 3)  : 0);
    }

    if ($rep == Avatica::Client::Protocol::Rep::JAVA_SQL_DATE()) {
        return $value if looks_like_number($value);
        my ($datetime, $milli) = split /\./, $value;
        my ($date, $time) = split /[tT ]/, $datetime;
        return Time::Piece->strptime($date, '%Y-%m-%d')->epoch / 86400;
    }

    if ($rep == Avatica::Client::Protocol::Rep::JAVA_SQL_TIMESTAMP()) {
        return $value if looks_like_number($value);
        my ($datetime, $milli) = split /\./, $value;
        my $sec = Time::Piece->strptime($datetime, '%Y-%m-%d %H:%M:%S')->epoch;
        return $sec * 1000 + ($milli ? substr($milli . '00', 0, 3) : 0);
    }

    return $value;
}

sub convert_jdbc_to_rep_type {
    my ($class, $jdbc_type) = @_;
    if ($jdbc_type > 0x7FFFFFFF) {
        $jdbc_type = -(($jdbc_type ^ 0xFFFFFFFF) + 1);
    }
    return $class->JAVA_TO_REP()->{$jdbc_type};
}

1;
