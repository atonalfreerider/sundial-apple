import SundialCore
import SwiftUI

/// MainActivity.showReportDialog: "Report this reading", one reason chosen from
/// ReadingReporter.Reason (Offensive or hateful to begin with), then SEND REPORT or CANCEL.
/// AppModel.sendReport hides the reading at once and sends the report.
struct ReportSheet: View {
    let onSend: (ReadingReporter.Reason) -> Void
    @State private var chosen = ReadingReporter.Reason.offensive
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(ReadingReporter.Reason.allCases, id: \.self) { reason in
                    Button {
                        chosen = reason
                    } label: {
                        HStack {
                            Text(reason.label)
                                .font(InstrumentControls.font(18))
                                .foregroundStyle(Color.primary)
                            Spacer()
                            if reason == chosen {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(InstrumentControls.color(InstrumentControls.brass))
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .accessibilityAddTraits(reason == chosen ? .isSelected : [])
                }
            }
            .navigationTitle("Report this reading")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("CANCEL") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("SEND REPORT") {
                        onSend(chosen)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
