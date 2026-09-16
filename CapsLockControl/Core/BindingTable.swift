import Foundation

/// 설정에서 뽑아낸, 엔진이 실제로 참조하는 표.
/// 키 식별자가 아니라 가상 키코드로 정규화되어 있다.
struct BindingTable: Sendable, Equatable {
    var layers: [LayerKey: [KeyCode: ShortcutAction]]

    init(layers: [LayerKey: [KeyCode: ShortcutAction]] = [:]) {
        self.layers = layers
    }

    func action(for layer: LayerKey, key: KeyCode) -> ShortcutAction? {
        layers[layer]?[key]
    }

    func contains(layer: LayerKey, key: KeyCode) -> Bool {
        layers[layer]?[key] != nil
    }

    var count: Int {
        layers.values.reduce(0) { $0 + $1.count }
    }
}
