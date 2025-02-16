# SurviveX

## The Problem

Imagine you're _lost and alone_ in a remote environment, you have no internet access to call for help or look up survival knowledge and time is **running out**. 

Whether it's a hiker with a broken leg, a soldier in combat, a responder during a natural disaster, or someone lost at sea, the _lack of internet connectivity_ and _immediate expert guidance_ can mean the difference between **life and death**.

## Our Solution

SurviveX is an offline-first embedded AI assistant that combines Edge AI on a hands free device like the Apple Vision Pro along with health monitoring and voice guidance to provide **real-time survival assistance**. 

### Our key features are:
1. Our Assistant that provides **step-by-step guidance**, helpful for providing stressed users with fast responses and ample opportunity for clarification throughout the process all in the _absence of an internet connection_.
2. Tracking vital signs through **Terra's API**, and provide step-by-step voice guidance. 
3. Our Machine Learning Model is designed to run on a **hands free device** like the Apple Vision Pro enabling survivors, first responders and soldiers to communicate via speech so your hands can focus on what matters : **survival**.
4. Fine tuning our Model to provide a user specific solution **governed by environment** indicative stress of the situation that users may be in. 

Whether you need to treat an injury, start a fire, fix up your broken car on the side of the highway, or navigate by stars, SurvivalX acts as your personal survival expert, adapting its guidance based on your speech and environmental conditions.

## How we built it
- We used **ExecuTorch** for on device inference for our Edge AI solution.
- The model we decided on was Meta's **Llama-3.2-1B-Instruct** since it was small and the most practical run on device.
- To fine tune our model we had to use **torchtune** - a PyTorch library for fine tuning our Llama Model on an instance of Nvidia's H-100 using Brev.dev. 
- We used **SwiftUI** for the interface on VisionOS and Swift for implementing the on device Llama model. 
- We used data from **Terra API** to stimulate tracking of heartbeats and vitals. 

## Installation

### From source

1. Clone PyTorch [ExecuTorch](https://pytorch.org/executorch/main/getting-started-setup) and it's submodules. No need to install.
2. In `examples/demo-apps/apple_ios` clone this repo.
3. In `SurviveX/SurviveX/Llama/` add `llaama3_2.pte` and `tokenizer.model` from our [Google Drive](https://drive.google.com/drive/folders/1fUfmI3E7uDgLrk0CRkHtEo1PfuL4Kqj8?usp=sharing).
4. Open in Xcode and build as specified [here](https://github.com/pytorch/executorch/blob/main/examples/demo-apps/apple_ios/LLaMA/docs/delegates/xnnpack_README.md#configure-the-xcode-project).

