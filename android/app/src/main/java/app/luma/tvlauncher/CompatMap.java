package app.luma.tvlauncher;

import java.util.Collections;
import java.util.HashMap;
import java.util.Map;
import java.util.Objects;

/** Map.of is only available from Android 11; Mi Box firmware can be older. */
final class CompatMap {
    private CompatMap() {}

    @SuppressWarnings("unchecked")
    static <K, V> Map<K, V> of(Object... pairs) {
        if (pairs.length % 2 != 0) throw new IllegalArgumentException("Expected key/value pairs");
        Map<K, V> result = new HashMap<>();
        for (int i = 0; i < pairs.length; i += 2) {
            K key = (K) Objects.requireNonNull(pairs[i]);
            V value = (V) Objects.requireNonNull(pairs[i + 1]);
            if (result.containsKey(key)) throw new IllegalArgumentException("Duplicate key");
            result.put(key, value);
        }
        return Collections.unmodifiableMap(result);
    }
}
