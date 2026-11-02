import CoreTransferable

/// Полезная нагрузка при перетаскивании хоста в группу.
struct HostDragItem: Transferable {
    let name: String

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(
            exporting: \.name,
            importing: { HostDragItem(name: $0) }
        )
    }
}
