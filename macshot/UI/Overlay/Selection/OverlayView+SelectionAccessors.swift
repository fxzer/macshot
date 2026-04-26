import AppKit

extension OverlayView {
    var selectedAnnotation: Annotation? {
        get { selectedAnnotations.count == 1 ? selectedAnnotations.first : nil }
        set {
            if let annotation = newValue {
                selectedAnnotations = [annotation]
            } else {
                selectedAnnotations = []
            }
        }
    }

    func isSelected(_ annotation: Annotation) -> Bool {
        selectedAnnotations.contains(where: { $0 === annotation })
    }
}
