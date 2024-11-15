import Foundation
import Collections

class Cache<K, V>: Sequence
where K: Hashable
{
    typealias Element = (key: K, value: V)
    typealias Iterator = Dictionary<K, V>.Iterator
    
    let maxCount: Int
    var store: [K: V] = [:]
    var lru: Deque<K> = []
    
    init(maxCount: Int) {
        self.maxCount = Swift.max(maxCount, 1)
    }
    
    subscript (key: K) -> V? {
        get {
            store[key]
        }
        set {
            if let newValue {
                store[key] = newValue
                lru.append(key)
                
                if lru.count > maxCount {
                    if let removedKey = lru.popFirst() {
                        store.removeValue(forKey: removedKey)
                    }
                }
            }
        }
    }
    
    var count: Int {
        return store.count
    }
    
    func removeAll() {
        store.removeAll()
        lru.removeAll()
    }
    
    func makeIterator() -> Iterator {
        return store.makeIterator()
    }
}

