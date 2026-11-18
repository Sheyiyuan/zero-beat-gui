package wire

import (
	"encoding/json"
	"fmt"
	"math"
	"reflect"
	"strconv"
	"time"
)

const maxSafeInteger = 9007199254740991

// Marshal validates JSON precision and contract invariants before encoding. RPC
// adapters should use this entry point instead of marshaling core structs.
func Marshal(v any) ([]byte, error) {
	if err := validate(reflect.ValueOf(v), "wire"); err != nil {
		return nil, err
	}
	return json.Marshal(v)
}
func validate(v reflect.Value, path string) error {
	if !v.IsValid() {
		return nil
	}
	if v.Kind() == reflect.Interface || v.Kind() == reflect.Pointer {
		if v.IsNil() {
			return nil
		}
		return validate(v.Elem(), path)
	}
	switch v.Type().Name() {
	case "Decimal":
		n, err := strconv.ParseInt(v.String(), 10, 64)
		if err != nil || strconv.FormatInt(n, 10) != v.String() {
			return fmt.Errorf("%s: noncanonical int64 string", path)
		}
		return nil
	case "Timestamp":
		s := v.String()
		t, err := time.Parse("2006-01-02T15:04:05.000Z", s)
		if err != nil || t.Format("2006-01-02T15:04:05.000Z") != s {
			return fmt.Errorf("%s: invalid canonical UTC timestamp", path)
		}
		return nil
	}
	switch v.Kind() {
	case reflect.Int, reflect.Int64:
		if v.Int() < -maxSafeInteger || v.Int() > maxSafeInteger {
			return fmt.Errorf("%s: exceeds JSON safe integer range", path)
		}
	case reflect.Float64:
		if math.IsNaN(v.Float()) || math.IsInf(v.Float(), 0) {
			return fmt.Errorf("%s: nonfinite number", path)
		}
	case reflect.Struct:
		if v.Type().Name() == "BrowseEntry" && v.FieldByName("Ref").IsNil() == v.FieldByName("Track").IsNil() {
			return fmt.Errorf("%s: exactly one of ref and track must be present", path)
		}
		for i := 0; i < v.NumField(); i++ {
			if err := validate(v.Field(i), path+"."+v.Type().Field(i).Name); err != nil {
				return err
			}
		}
	case reflect.Slice:
		if v.IsNil() {
			return fmt.Errorf("%s: arrays must be non-null", path)
		}
		for i := 0; i < v.Len(); i++ {
			if err := validate(v.Index(i), path+"[]"); err != nil {
				return err
			}
		}
	case reflect.Map:
		if v.IsNil() {
			return fmt.Errorf("%s: maps must be non-null", path)
		}
		for _, k := range v.MapKeys() {
			if err := validate(v.MapIndex(k), path+"[]"); err != nil {
				return err
			}
		}
	}
	return nil
}
