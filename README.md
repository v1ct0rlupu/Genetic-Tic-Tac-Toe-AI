# EvoTic — Genetic Tic-Tac-Toe AI

**An experimental Tic-Tac-Toe artificial intelligence that learns through genetic algorithms and neural networks.**

EvoTic is an open-source C++ project exploring evolutionary computation by training artificial intelligence to play Tic-Tac-Toe. Instead of manually programming strategies, the project uses populations of neural networks that compete against each other, evolve through natural-selection-inspired mechanisms, and gradually improve their decision-making.

The project includes two implementations:
- **CPU version:** A standard C++ implementation that runs without specialized hardware.
- **NVIDIA GPU version:** A CUDA-powered implementation designed to accelerate population evaluation using parallel GPU computation.

The project is free to use, modify, and contribute to.

---

## Features

- **Neural Networks:** Individuals use neural networks to evaluate possible moves.
- **Genetic Algorithms:** Selection, crossover, mutation, and elitism drive evolution.
- **Population-Based Training:** Multiple AI individuals compete to determine which strategies survive.
- **GPU Acceleration:** The CUDA implementation evaluates matches in parallel on NVIDIA GPUs.
- **Random Opponent Benchmarking:** The GPU implementation also tests individuals against random opponents.
- **AI vs. AI:** Watch selected individuals compete against each other.
- **Human vs. AI:** Play Tic-Tac-Toe against a trained individual.
- **Training Persistence:** Save and load populations to continue training later.
- **Long-Term Training:** Designed for experiments involving large numbers of generations.

## How It Works

Each individual represents a neural network with its own set of weights.

The neural network receives the current board as input:

- `1` represents the AI's own piece.
- `-1` represents the opponent's piece.
- `0` represents an empty cell.

It evaluates the board and produces scores for the nine possible positions. The AI selects the available position with the highest output.

The genetic algorithm then evolves the population through four main stages:

1. **Evaluation:** Individuals compete in simulated Tic-Tac-Toe matches.
2. **Selection:** Better-performing individuals have a higher chance of becoming parents.
3. **Crossover:** Neural network weights are inherited from two parents.
4. **Mutation:** Random changes introduce variation into the next generation.

Elitism preserves the best-performing individual so that the best result from the previous generation is not lost during reproduction.

The process repeats across generations.

## Implementations

### 1. CPU Version

The original implementation uses standard C++ and does not require an NVIDIA GPU.

**Technologies:**
- C++
- Neural networks
- Genetic algorithms
- File-based population persistence

**Requirements:**
- A C++ compiler supporting C++11 or newer.
- Windows, Linux, or macOS.

**Compile:**

```bash
g++ -O2 -std=c++11 main.cpp -o evotic
```

Run on Linux/macOS:

```bash
./evotic
```

On Windows:

```powershell
evotic.exe
```

### 2. NVIDIA CUDA Version

The CUDA implementation introduces GPU-accelerated population evaluation.

Instead of evaluating every match sequentially on the CPU, CUDA kernels distribute match simulations across GPU threads.

It also introduces:
- A larger population (512 individuals by default).
- Tournament selection.
- A deeper neural network with one hidden layer.
- Biases in neural network layers.
- Random-opponent evaluation.
- Binary population saving for faster loading and storage.
- Training benchmarks and elapsed-time reporting.

**Neural network architecture:**

```text
9 Input Neurons
       |
       v
18 Hidden Neurons (ReLU)
       |
       v
9 Output Neurons
       |
       v
Move Selection
```

**Requirements:**
- An NVIDIA GPU with CUDA support.
- NVIDIA CUDA Toolkit.
- A compatible NVIDIA driver.
- CUDA-capable C++ compiler (`nvcc`).

**Compile:**

```bash
nvcc -O2 -arch=native main.cu -o evotic
```

If your CUDA compiler does not support `-arch=native`, remove that flag and compile with:

```bash
nvcc -O2 main.cu -o evotic
```

Run:

```bash
./evotic
```

On Windows, run the generated executable:

```powershell
evotic.exe
```

> The CUDA implementation requires an NVIDIA GPU. The CPU implementation does not.

---

## Main Menu

Both implementations provide an interactive terminal menu.

| Option | Description |
|---|---|
| 1 | Train the AI for a chosen number of generations |
| 2 | Watch an AI vs. AI match |
| 3 | Play against the selected AI |
| 0 | Save progress and exit |

Training progress is saved so that you can continue from the previously stored population.

## Configuration

The CUDA implementation exposes several parameters near the beginning of `main.cu`:

| Parameter | Default | Description |
|---|---:|---|
| `POP` | 512 | Population size |
| `TURNIR` | 3 | Tournament selection candidates |
| `MECIURI_RANDOM` | 1000 | Random-opponent matches per individual |
| `RATA_MUTATIE` | 0.05 | Mutation probability |
| `PAS_MUTATIE` | 0.2 | Maximum mutation adjustment |

You can modify these values to experiment with different evolutionary configurations.

## Project Goals

The long-term objective is to investigate how neural networks can develop game-playing strategies through evolutionary algorithms.

Some of the planned experiments include:

- Training over hundreds of thousands or millions of generations.
- Comparing CPU and GPU training performance.
- Experimenting with population sizes and mutation rates.
- Improving opponent evaluation.
- Measuring performance against stronger strategies.
- Investigating whether the evolved AI can approach optimal Tic-Tac-Toe play.

## Current Status

**Experimental / Work in Progress**

EvoTic is an educational and experimental project. The implementations are still evolving, and successful training is not guaranteed to produce optimal play.

The CUDA implementation is a separate, more advanced implementation and uses a different neural network architecture and population format from the original CPU version. Their saved populations are not interchangeable.

## Contributing

Contributions, suggestions, bug reports, and experiments are welcome!

If you want to contribute:

1. Fork the repository.
2. Create a branch for your changes.
3. Make your improvements.
4. Submit a pull request.

Whether you're interested in C++, CUDA, neural networks, or genetic algorithms, you're welcome to explore the project.

## License

This project is intended to be released under the **MIT License**.

You are free to use, copy, modify, merge, publish, distribute, sublicense, and sell copies of the software, subject to the conditions of the license.

See [LICENSE](LICENSE) for details.

---

**Built with C++, neural networks, genetic algorithms, and NVIDIA CUDA.**

*The goal: let evolution teach an AI how to play Tic-Tac-Toe.*
