//
//  Activity.swift
//  SceneManager
//
//  Created by Hans Kröner on 15/04/2025.
//

import SwiftUI
import deCONZ

struct Activity: View {
    private let columns = [GridItem(.flexible(minimum: 200))]
    private let timestampFormat = Date.FormatStyle()
        .day(.twoDigits)
        .month(.twoDigits)
        .year()
        .hour()
        .minute()
        .second(.twoDigits)
        .secondFraction(.fractional(3))
    
    var body: some View {
        Table(RESTModel.shared.activity.entries) {
            TableColumn("Timestamp") { activity in
                Text(activity.timestamp.formatted(timestampFormat))
                    .textSelection(.enabled)
                    .lineLimit(1)
            }
            
            TableColumn("Action") { activity in
                HStack {
                    switch activity.outcome {
                    case .success:
                        Image(systemName: "checkmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .green)
                        
                    case .failure:
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .red)
                        
                    default:
                        Image(systemName: "questionmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .orange)
                    }
                    
                    Text(activity.path)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            
            TableColumn("Description") { activity in
                switch activity.outcome {
                case .failure(let description):
                    Text(description)
                        .textSelection(.enabled)
                        .lineLimit(1)
                
                default:
                    Text("")
                }
            }
            
            TableColumn("Request") { activity in
                Text(activity.request ?? "")
                    .textSelection(.enabled)
                    .lineLimit(1)
            }
            
            TableColumn("Response") { activity in
                Text(activity.response ?? "")
                    .textSelection(.enabled)
                    .lineLimit(1)
            }
        }
    }
}

#Preview {
    Activity()
}
