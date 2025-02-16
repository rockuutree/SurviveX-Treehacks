/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree.
 */

import LLaMARunner
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
  @State private var prompt = ""
  @State private var messages: [Message] = []
  @State private var showingLogs = false
  @State private var pickerType: PickerType?
  @State private var isGenerating = false
  @State private var shouldStopGenerating = false
  @State private var shouldStopShowingToken = false
  private let runnerQueue = DispatchQueue(
    label: "org.pytorch.executorch.llama")
  @State private var runnerHolder: Runner?
  @StateObject private var resourceMonitor = ResourceMonitor()
  @StateObject private var logManager = LogManager()

  @FocusState private var textFieldFocused: Bool

  enum PickerType {
    case model
    case tokenizer
  }

  // Define resource URLs for the model.
  private let modelURL = Bundle.main.url(
    forResource: "llama3_2", withExtension: "pte")
  private let tokenizerURL = Bundle.main.url(
    forResource: "tokenizer", withExtension: "model")

  private var validModelAndTokenizer: Bool {
    modelURL != nil && tokenizerURL != nil
  }

  private var placeholder: String {
    validModelAndTokenizer
      ? "What is your situation?" : ""
  }

  var body: some View {
    NavigationView {
      VStack {
        MessageListView(messages: $messages)
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

        HStack {
          TextField(placeholder, text: $prompt, axis: .vertical)
            .padding(8)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(20)
            .lineLimit(1...10)
            .overlay(
              RoundedRectangle(cornerRadius: 20)
                .stroke(
                  validModelAndTokenizer ? Color.blue : Color.gray,
                  lineWidth: 1)
            )
            .disabled(!validModelAndTokenizer)
            .focused($textFieldFocused)
            .onAppear { textFieldFocused = false }

          Button(action: isGenerating ? stop : generate) {
            Image(
              systemName: isGenerating
                ? "stop.circle" : "arrowshape.up.circle.fill"
            )
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(height: 28)
          }
          .disabled(
            isGenerating
              ? shouldStopGenerating
              : (!validModelAndTokenizer || prompt.isEmpty))
        }
        .padding([.leading, .trailing, .bottom], 10)
      }
      .navigationBarItems(
        leading:
          Menu {
            Section(header: Text("Memory")) {
              Text("Used: \(resourceMonitor.usedMemory) Mb")
              Text("Available: \(resourceMonitor.usedMemory) Mb")
            }
          } label: {
            Text("\(resourceMonitor.usedMemory) Mb")
          }
          .onAppear {
            resourceMonitor.start()
          }
          .onDisappear {
            resourceMonitor.stop()
          },
        trailing:
          Button(action: { showingLogs = true }) {
            Image(systemName: "list.bullet.rectangle")
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

  private func generate() {
    // Shortcut exit if there is no prompt or no model.
    guard !prompt.isEmpty else { return }
    guard let modelPath = modelURL?.path() else { return }
    guard let tokenPath = tokenizerURL?.path() else { return }

    isGenerating = true
    shouldStopGenerating = false
    shouldStopShowingToken = false
    let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    let seq_len = 768  // text: 256, vision: 768

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

      // Generate response.
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
      do {
        var tokens: [String] = []

        let llama3_prompt =
          "<|begin_of_text|><|start_header_id|>user<|end_header_id|>\(text)<|eot_id|><|start_header_id|>assistant<|end_header_id|>"

        try runnerHolder?.generate(
          llama3_prompt, sequenceLength: seq_len
        ) { token in

          NSLog(">>> token={\(token)}")
          if token != llama3_prompt {
            // hack to fix the issue that extension/llm/runner/text_token_generator.h
            // keeps generating after <|eot_id|>
            if token == "<|eot_id|>" {
              shouldStopShowingToken = true
            } else {
              tokens.append(
                token.trimmingCharacters(in: .newlines))
              if tokens.count > 2 {
                let text = tokens.joined()
                let count = tokens.count
                tokens = []
                DispatchQueue.main.async {
                  var message = messages.removeLast()
                  message.text += text
                  message.tokenCount += count
                  message.dateUpdated = Date()
                  messages.append(message)
                }
              }
              if shouldStopGenerating {
                runnerHolder?.stop()
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
      #selector(UIResponder.resignFirstResponder), to: nil, from: nil,
      for: nil)
  }
}
