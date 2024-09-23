import TokamakDOM
import TokamakAppDemoLibrary

@main
struct TokamakApp: App {
    var body: some Scene {
        WindowGroup("Tokamak App") {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State var dynamicText = ""
    
    var body: some View {
        // Blank project starts out with hello world:
        // Text("Hello, World!")
        
        VStack {
            // Header
            HStack {
                Spacer()
                
                Button("Amazing Co") { dynamicText = "Logo Button Pressed"}
                
                Spacer()
                
                HStack {
                    Button("Hardware") { onButtonPress(message: "Hardware Button Pressed") }
                    Button("Software") { onButtonPress(message: "Software Button Pressed") }
                    Button("Quantum") { onButtonPress(message: "Quantum Button Pressed") }
                    Button("Swift") { onButtonPress(message: "Swift Button Pressed") }
                    Button("Company") { onButtonPress(message: "Company Button Pressed") }
                    Button("Careers") { onButtonPress(message: "Careers Button Pressed") }
                }
                
                Spacer()
                
                Button("Sign In") { dynamicText = "Sign In Button Pressed"}
                
                Spacer()
            }
            .frame(height: 100)
            .background(.white)
            
            Text("Great things coming soon…")
                .font(.title)
                .frame(height: 400)
            
            Text(dynamicText)
                .font(.title)
                .frame(height: 400)
                .background(.gray)
        }
    }
    
    private func onButtonPress(message: String) {
        dynamicText = message
    }
}
