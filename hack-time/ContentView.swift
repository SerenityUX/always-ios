import SwiftUI

struct AsyncImageView: View {
    let url: URL

    @State private var image: UIImage? = nil
    @State private var isLoading: Bool = true

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
            } else if isLoading {
                ProgressView()
                    .frame(width: 44, height: 44)
            } else {
                Image(systemName: "person.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44, height: 44)
            }
        }
        .onAppear {
            loadImage()
        }
    }

    private func loadImage() {
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil else {
                DispatchQueue.main.async {
                    self.isLoading = false
                }
                return
            }
            if let uiImage = UIImage(data: data) {
                DispatchQueue.main.async {
                    self.image = uiImage
                    self.isLoading = false
                }
            }
        }
        task.resume()
    }
}

struct ContentView: View {
    let startTime: Date
    let endTime: Date
    
    init() {
        let calendar = Calendar.current
        let now = Date()
        
        // Set start time to today at 9:00 AM in the device's local time zone
        var startComponents = calendar.dateComponents([.year, .month, .day], from: now)
        startComponents.hour = 9
        startComponents.minute = 0
        startComponents.second = 0
        self.startTime = calendar.date(from: startComponents)!
        
        // Set end time to 33 hours after start time
        self.endTime = calendar.date(byAdding: .hour, value: 33, to: self.startTime)!
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                Text("Run Of Show")
                    .font(.largeTitle)
                    .fontWeight(.medium)

                Spacer()

                AsyncImageView(url: URL(string: "https://thispersondoesnotexist.com")!)
            }
            .padding()

            ScrollView {
                VStack {
                    ForEach(hoursBetween(start: startTime, end: endTime), id: \.self) { date in
                        VStack {
                            HStack {
                                VStack(alignment: .leading) {
                                    if shouldShowWeekday(for: date) {
                                        Text(formatWeekday(date: date))
                                            .foregroundColor(Color(hue: 1.0, saturation: 0.0, brightness: 0.459))
                                    }
                                    Text(formatTime(date: date))
                                        .foregroundColor(Color(hue: 1.0, saturation: 0.0, brightness: 0.459))
                                        .frame(width: 72, alignment: .leading)
                                }
                                VStack {
                                    Divider()
                                }
                            }
                            Spacer()
                        }
                        .frame(height: 64.0)
                    }
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private func formatTime(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        return formatter.string(from: date).lowercased()
    }
    
    private func formatWeekday(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date).uppercased()
    }
    
    private func shouldShowWeekday(for date: Date) -> Bool {
        let calendar = Calendar.current
        if date == startTime {
            return true
        }
        let previousHour = calendar.date(byAdding: .hour, value: -1, to: date)!
        return !calendar.isDate(date, inSameDayAs: previousHour)
    }
    
    private func hoursBetween(start: Date, end: Date) -> [Date] {
        var dates: [Date] = []
        var currentDate = start
        
        while currentDate <= end {
            dates.append(currentDate)
            currentDate = Calendar.current.date(byAdding: .hour, value: 1, to: currentDate)!
        }
        
        return dates
    }
}

#Preview {
    ContentView()
}
