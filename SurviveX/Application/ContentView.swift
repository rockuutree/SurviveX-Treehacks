import AVFoundation
import LLaMARunner
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
  // UI and application state.
  @State private var prompt = ""
  @State private var messages: [Message] = []
  @State private var showingLogs = false
  @State private var isGenerating = false
  @State private var shouldStopGenerating = false
  @State private var isRecording = false

  // Model state.
  private let runnerQueue = DispatchQueue(label: "org.pytorch.executorch.llama")
  @State private var runnerHolder: Runner?
  @StateObject private var resourceMonitor = ResourceMonitor()
  @StateObject private var logManager = LogManager()

  // Speech components.
  private let speechRecognitionService = SpeechRecognitionService()
  private let speechSynthesizer = AVSpeechSynthesizer()

  // Input field state.
  @FocusState private var textFieldFocused: Bool

  private var placeholder: String {
    validModelAndTokenizer ? "What is your situation?" : ""
  }

  // Define resource URLs for the model.
  private let modelURL = Bundle.main.url(
    forResource: "llama3_2", withExtension: "pte")
  private let tokenizerURL = Bundle.main.url(
    forResource: "tokenizer", withExtension: "model")

  private var validModelAndTokenizer: Bool {
    modelURL != nil && tokenizerURL != nil
  }

  var body: some View {
    NavigationView {
      ZStack {
        // Background color.
        Color.green.opacity(0.2)
          .ignoresSafeArea()

        VStack {
          // Placeholder text when no messages.
          if messages.isEmpty {
            Text("Ask for help")
              .font(.system(size: 36, weight: .bold))
              .foregroundColor(.black)
              .padding(.top, 40)
          }

          // Terra HR view.
          HeartRateView()
            .padding()

          // Conversation history.
          MessageListView(messages: $messages)
            .font(.system(size: 24))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .simultaneousGesture(
              DragGesture().onChanged { value in
                if value.translation.height > 10 {
                  hideKeyboard()
                }
                textFieldFocused = false
              }
            )
            .onTapGesture {
              textFieldFocused = false
            }

          // Input section.
          VStack {
            HStack(spacing: 20) {
              // Input view.
              TextField(placeholder, text: $prompt, axis: .vertical)
                .font(.system(size: 24, weight: .bold))  // Bold black text
                .tint(.black)
                .padding(16)  // More padding
                .foregroundColor(.black)
                .background(Color.white.opacity(0.8))
                .cornerRadius(30)  // Larger corner radius
                .lineLimit(1...10)
                .overlay(
                  RoundedRectangle(cornerRadius: 30)
                    .stroke(
                      validModelAndTokenizer ? Color.green : Color.gray,
                      lineWidth: 2)  // Green border
                )
                .disabled(!validModelAndTokenizer)
                .focused($textFieldFocused)
                .onAppear { textFieldFocused = false }
                .frame(maxWidth: .infinity)
              // Generate/Stop Button
              Button(action: isGenerating ? stop : generate) {
                Image(
                  systemName: isGenerating
                    ? "stop.circle" : "arrowshape.up.circle.fill"
                )
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 56, height: 56)  // Larger button
                .foregroundStyle(.green)
                .background(
                  Circle()
                    .fill(Color.white.opacity(0.8))
                    .frame(width: 64, height: 64)
                )
              }
              .disabled(
                isGenerating
                  ? shouldStopGenerating
                  : (!validModelAndTokenizer || prompt.isEmpty)
              )
              .padding(8)
            }

            // Voice Recording Button (generate on stop).
            Button {
              withAnimation {
                toggleRecording()
              }
            } label: {
              Image(
                systemName: !isRecording ? "waveform" : "stop.circle.fill"
              )
              .resizable()
              .aspectRatio(contentMode: .fit)
              .frame(width: 56, height: 56)  // Larger button
              .foregroundStyle(isRecording ? .red : .green)
              .background(
                Circle()
                  .fill(Color.white.opacity(0.8))
                  .frame(width: 64, height: 64)
              )
            }
            .disabled(isGenerating)
            .buttonStyle(.borderless)
            .padding(8)
          }
          .padding([.leading, .trailing], 32)  // Wider horizontal padding
          .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity)  // Increased maximum width
      }
      .navigationBarItems(
        leading:
          HStack {
            // Memory consumption utility.
            Menu {
              Section(header: Text("Memory")) {
                Text("Used: \(resourceMonitor.usedMemory) Mb")
                  .font(.title3)
                Text("Available: \(resourceMonitor.usedMemory) Mb")
                  .font(.title3)
              }
            } label: {
              Text("\(resourceMonitor.usedMemory) Mb")
                .font(.title3)
                .foregroundStyle(.green)
            }
            .onAppear {
              resourceMonitor.start()
            }
            .onDisappear {
              resourceMonitor.stop()
            }

            // Interaction logs.
            Button(action: { showingLogs = true }) {
              Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 28))
                .foregroundStyle(.green)
            }
          },
        trailing:
          Button(action: { self.messages.removeAll() }) {
            Image(systemName: "clear")
              .font(.system(size: 28))
              .foregroundStyle(.green)
          }
      )
      .sheet(isPresented: $showingLogs) {
        NavigationView {
          LogView(logManager: logManager)
        }
      }
    }
    .navigationViewStyle(StackNavigationViewStyle())
  }

  // Speech to text.
  func toggleRecording() {
    isRecording.toggle()

    if isRecording {
      Task {
        if await speechRecognitionService.startRecording() {
          // Started successfully
        } else {
          isRecording = false
        }
      }
    } else {
      speechRecognitionService.stopRecording()
      // Get the final transcription
      let transcribedText = speechRecognitionService.getCurrentTranscription()
      if !transcribedText.isEmpty {
        self.prompt = transcribedText

        // Send off prompt once collected.
        generate()
      }
    }
  }

  // Text-to-Speech Function.
  private func speakText(_ text: String) {
    let utterance = AVSpeechUtterance(string: text)
    utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
    utterance.rate = 0.5  // Slower speed for better clarity
    utterance.pitchMultiplier = 1.0
    utterance.volume = 1.0

    // Stop any ongoing speech
    if speechSynthesizer.isSpeaking {
      speechSynthesizer.stopSpeaking(at: .immediate)
    }

    speechSynthesizer.speak(utterance)
  }

  // Send query to model.
  private func generate() {
    // Shortcut exit if there is no prompt or no model.
    guard !prompt.isEmpty else { return }
    guard let modelPath = modelURL?.path() else { return }
    guard let tokenPath = tokenizerURL?.path() else { return }

    isGenerating = true
    shouldStopGenerating = false
    let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    let seq_len = 8192

    prompt = ""
    hideKeyboard()

    messages.append(Message(text: text))
    messages.append(Message(type: .llamagenerated))

    runnerQueue.async {
      defer {
        DispatchQueue.main.async {
          isGenerating = false
        }
      }

      // Create runner.
      runnerHolder =
        runnerHolder ?? Runner(modelPath: modelPath, tokenizerPath: tokenPath)

      // Load model.
      guard !shouldStopGenerating else { return }
      if let runner = runnerHolder, !runner.isLoaded() {
        var error: Error?
        let startLoadTime = Date()
        do {
          try runner.load()
        } catch let loadError {
          error = loadError
        }

        let loadTime = Date().timeIntervalSince(startLoadTime)
        DispatchQueue.main.async {
          withAnimation {
            var message = messages.removeLast()
            message.type = .info
            if let error {
              message.text =
                "Model loading failed: error \((error as NSError).code)"
            } else {
              message.text =
                "Model loaded in \(String(format: "%.2f", loadTime)) s"
            }
            messages.append(message)
            if error == nil {
              messages.append(Message(type: .llamagenerated))
            }
          }
        }
        if error != nil {
          return
        }
      }

      guard !shouldStopGenerating else {
        DispatchQueue.main.async {
          withAnimation {
            _ = messages.removeLast()
          }
        }
        return
      }

      // Make prompt and send.
      do {
        // Rebuild chat history.
        var history =
          "<|begin_of_text|><|start_header_id|>system<|end_header_id|>You are an AI assistant that safely guides users through life-threatening emergency situation. Provide a single step of instruction between each user prompt.<|eot_id|>"
        for message in messages {
          // Skip info messages.
          if message.type == .info {
            continue
          }

          // Skip empty messages.
          if message.text.isEmpty {
            continue
          }

          // Update history with each message.
          history +=
            "<|start_header_id|>\(message.type == .prompted ? "user" : "assistant")<|end_header_id|>\(message.text)<|eot_id|>"
        }

        // Build prompt.
        let llama3_prompt =
          "\(history)<|start_header_id|>user<|end_header_id|>\(text). What is the \(self.messages.count == 2 ? "first" : "next") step?<|eot_id|><|start_header_id|>assistant<|end_header_id|>"

        try runnerHolder?.generate(llama3_prompt, sequenceLength: seq_len) {
          token in
          // Stop generating when marked.
          if shouldStopGenerating {
            runnerHolder?.stop()
          }

          // Otherwise, process.
          NSLog(">>> token={\(token)}")
          if token != llama3_prompt {
            if token == "<|eot_id|>" {
              // Possible race condition with full text not completely generated yet.
              // Speak the complete generated text.
              DispatchQueue.main.async {
                speakText(messages.last?.text ?? "")
              }
            } else {
              DispatchQueue.main.async {
                if var lastMessage = messages.last {
                  // Extend message.
                  lastMessage.text += token

                  // Remove newlines and blank from the start of the text.
                  lastMessage.text = String(
                    lastMessage.text.trimmingPrefix(while: \.isNewline))

                  lastMessage.tokenCount += 1
                  lastMessage.dateUpdated = Date()
                  messages[messages.count - 1] = lastMessage
                }
              }
            }
          }
        }
      } catch {
        DispatchQueue.main.async {
          withAnimation {
            var message = messages.removeLast()
            message.type = .info
            message.text =
              "Text generation failed: error \((error as NSError).code)"
            messages.append(message)
          }
        }
      }
    }
  }

  private func stop() {
    shouldStopGenerating = true
  }
}

extension View {
  func hideKeyboard() {
    UIApplication.shared.sendAction(
      #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
  }
}
