// Compilare: nvcc -O2 -arch=native main.cu -o tictactoe
// (daca nvcc nu stie -arch=native, scoate-l; merge si fara)

#include <iostream>
#include <cstdlib>
#include <fstream>
#include <thread>
#include <chrono>
#include <iomanip>
#include <limits>
#include <vector>
#include <random>
#include <cctype>
#include <cuda_runtime.h>
using namespace std;

// functiile marcate HD ruleaza si pe CPU, si pe GPU
#define HD __host__ __device__

// verifica orice apel CUDA si opreste programul daca a picat ceva
#define CUDA_OK(apel)                                                   \
    do {                                                                \
        cudaError_t eroare = (apel);                                    \
        if(eroare != cudaSuccess) {                                     \
            cout << "Eroare CUDA: " << cudaGetErrorString(eroare)       \
                 << endl;                                               \
            exit(1);                                                    \
        }                                                               \
    } while(0)

// ==========================================
// SETARI
// ==========================================

const int POP = 512;                 // marimea populatiei (GPU-ul se descurca usor cu mult mai multe)
const int TURNIR = 3;                // cati candidati se iau la selectia parintilor
const int MECIURI_RANDOM = 1000;     // meciuri contra unui jucator random, per individ si per generatie
const float RATA_MUTATIE = 0.05f;    // sansa ca o pondere sa fie mutata
const float PAS_MUTATIE = 0.2f;      // cat de mult se poate schimba o pondere

// reteaua: 9 intrari -> 18 neuroni ascunsi (ReLU) -> 9 iesiri
const int INTRARI = 9;
const int ASCUNS = 18;
const int IESIRI = 9;
const int NR_PONDERI = INTRARI * ASCUNS + ASCUNS      // strat 1: ponderi + bias
                     + ASCUNS * IESIRI + IESIRI;      // strat 2: ponderi + bias

const char* FISIER_SALVARE = "populatie_gpu.bin";

// un individ = toate ponderile retelei intr-un singur vector
struct Individ {
    float p[NR_PONDERI];
};

// ==========================================
// NUMERE ALEATOARE (doar pe CPU)
// ==========================================

mt19937 rng(random_device{}());

float aleator(float minim, float maxim) {
    return uniform_real_distribution<float>(minim, maxim)(rng);
}

int intAleator(int n) {
    return uniform_int_distribution<int>(0, n - 1)(rng);
}

// ==========================================
// AFISARE TABLA
// ==========================================

void afiseazaTabla(char tabla[3][3]) {
    cout << "\n";

    for(int i = 0; i < 3; i++) {
        cout << " ";

        for(int j = 0; j < 3; j++) {
            if(tabla[i][j] == ' ')
                cout << i * 3 + j + 1;
            else
                cout << tabla[i][j];

            if(j < 2)
                cout << " | ";
        }

        cout << "\n";

        if(i < 2)
            cout << "---+---+---\n";
    }

    cout << "\n";
}

// ==========================================
// LOGICA JOCULUI
// ==========================================

HD void golesteTabla(char tabla[3][3]) {
    for(int i = 0; i < 3; i++) {
        for(int j = 0; j < 3; j++) {
            tabla[i][j] = ' ';
        }
    }
}

HD bool mutareValida(char tabla[3][3], int linie, int coloana) {
    if(linie < 0 || linie > 2 || coloana < 0 || coloana > 2)
        return false;

    if(tabla[linie][coloana] != ' ')
        return false;

    return true;
}

HD bool efectueazaMutare(char tabla[3][3], int linie, int coloana, char jucator) {
    if(!mutareValida(tabla, linie, coloana))
        return false;

    tabla[linie][coloana] = jucator;
    return true;
}

HD char verificaCastigator(char tabla[3][3]) {
    for(int i = 0; i < 3; i++) {
        if(tabla[i][0] == tabla[i][1] &&
           tabla[i][1] == tabla[i][2] &&
           tabla[i][0] != ' ')
            return tabla[i][0];
    }

    for(int i = 0; i < 3; i++) {
        if(tabla[0][i] == tabla[1][i] &&
           tabla[1][i] == tabla[2][i] &&
           tabla[0][i] != ' ')
            return tabla[0][i];
    }

    if(tabla[0][0] == tabla[1][1] &&
       tabla[1][1] == tabla[2][2] &&
       tabla[0][0] != ' ')
        return tabla[0][0];

    if(tabla[0][2] == tabla[1][1] &&
       tabla[1][1] == tabla[2][0] &&
       tabla[0][2] != ' ')
        return tabla[0][2];

    return ' ';
}

HD bool tablaPlina(char tabla[3][3]) {
    for(int i = 0; i < 3; i++) {
        for(int j = 0; j < 3; j++) {
            if(tabla[i][j] == ' ')
                return false;
        }
    }

    return true;
}

// ==========================================
// RETEA NEURONALA
// ==========================================

// 1 = piesa mea, -1 = piesa adversarului, 0 = gol
HD void transformaTabla(char tabla[3][3], float intrare[INTRARI], char simbol) {
    for(int i = 0; i < 3; i++) {
        for(int j = 0; j < 3; j++) {
            if(tabla[i][j] == simbol)
                intrare[i*3+j] = 1;
            else if(tabla[i][j] == ' ')
                intrare[i*3+j] = 0;
            else
                intrare[i*3+j] = -1;
        }
    }
}

// un strat dens: iesire[o] = bias[o] + suma(ponderi[o][k] * intrare[k])
HD void strat(const float* intrare, int nIntrari,
              const float* ponderi, const float* bias,
              float* iesire, int nIesiri) {

    for(int o = 0; o < nIesiri; o++) {
        float suma = bias[o];

        for(int k = 0; k < nIntrari; k++) {
            suma += ponderi[o * nIntrari + k] * intrare[k];
        }

        iesire[o] = suma;
    }
}

HD void relu(float* valori, int n) {
    for(int i = 0; i < n; i++) {
        if(valori[i] < 0)
            valori[i] = 0;
    }
}

// alege cea mai mare iesire dintre pozitiile libere
HD int alegeMutare(float rezultate[IESIRI], char tabla[3][3]) {
    int pozitie = -1;
    float maxim = -1e30f;

    for(int i = 0; i < IESIRI; i++) {
        if(tabla[i / 3][i % 3] == ' ' && rezultate[i] > maxim) {
            maxim = rezultate[i];
            pozitie = i;
        }
    }

    return pozitie;
}

HD int mutareAI(char tabla[3][3], const Individ& individ, char simbol) {
    // decupam ponderile individului in cele 4 bucati ale retelei
    const float* ponderi1 = individ.p;
    const float* bias1    = ponderi1 + INTRARI * ASCUNS;
    const float* ponderi2 = bias1 + ASCUNS;
    const float* bias2    = ponderi2 + ASCUNS * IESIRI;

    float intrare[INTRARI];
    float ascuns[ASCUNS];
    float rezultate[IESIRI];

    transformaTabla(tabla, intrare, simbol);

    strat(intrare, INTRARI, ponderi1, bias1, ascuns, ASCUNS);
    relu(ascuns, ASCUNS);                                  // ReLU doar pe stratul ascuns
    strat(ascuns, ASCUNS, ponderi2, bias2, rezultate, IESIRI);

    return alegeMutare(rezultate, tabla);
}

// ==========================================
// INITIALIZARE POPULATIE
// ==========================================

void initializeazaPopulatie(vector<Individ>& populatie) {
    populatie.resize(POP);

    for(int k = 0; k < POP; k++) {
        for(int i = 0; i < NR_PONDERI; i++) {
            populatie[k].p[i] = aleator(-1, 1);
        }
    }
}

// ==========================================
// FITNESS SI MECIURI
// ==========================================

HD int fitness(char tabla[3][3], char simbol) {
    char castigator = verificaCastigator(tabla);

    if(castigator == simbol)
        return 10;

    if(castigator == ' ' && tablaPlina(tabla))
        return 3;

    return 0;
}

// individul x joaca cu X (mutare prima), individul o joaca cu O
HD void joacaMeci(const Individ& x, const Individ& o, int scoruri[2]) {

    char tabla[3][3];
    golesteTabla(tabla);

    char jucator = 'X';

    while(true) {
        const Individ& individ = (jucator == 'X') ? x : o;

        int pozitie = mutareAI(tabla, individ, jucator);
        efectueazaMutare(tabla, pozitie / 3, pozitie % 3, jucator);

        if(verificaCastigator(tabla) != ' ' || tablaPlina(tabla))
            break;

        jucator = (jucator == 'X') ? 'O' : 'X';
    }

    scoruri[0] = fitness(tabla, 'X');
    scoruri[1] = fitness(tabla, 'O');
}

// ==========================================
// JUCATOR RANDOM (ancora de fitness + benchmark)
// ==========================================
// Turneul dintre indivizi da doar un fitness relativ (populatia se joaca intre ea).
// Meciurile contra unui jucator care muta la intamplare dau o masura "reala"
// si tin populatia cu picioarele pe pamant.

// generator simplu (xorshift) care merge si pe GPU
HD unsigned int urmatorulRandom(unsigned int& stare) {
    stare ^= stare << 13;
    stare ^= stare >> 17;
    stare ^= stare << 5;
    return stare;
}

// returneaza 1 = AI castiga, 0 = remiza, -1 = AI pierde
HD int meciContraRandom(const Individ& individ, char simbolAI, unsigned int& stare) {

    char tabla[3][3];
    golesteTabla(tabla);

    char jucator = 'X';

    while(true) {
        int pozitie;

        if(jucator == simbolAI) {
            pozitie = mutareAI(tabla, individ, jucator);
        }
        else {
            do {
                pozitie = urmatorulRandom(stare) % 9;
            } while(!mutareValida(tabla, pozitie / 3, pozitie % 3));
        }

        efectueazaMutare(tabla, pozitie / 3, pozitie % 3, jucator);

        if(verificaCastigator(tabla) != ' ' || tablaPlina(tabla))
            break;

        jucator = (jucator == 'X') ? 'O' : 'X';
    }

    char castigator = verificaCastigator(tabla);

    if(castigator == simbolAI)
        return 1;

    if(castigator == ' ')
        return 0;

    return -1;
}

// ==========================================
// EVALUAREA POPULATIEI (pe GPU)
// ==========================================

// Fiecare thread joaca UN meci: individul i (cu X) contra individului j (cu O).
// Cu toate perechile (i, j), fiecare individ joaca si cu X, si cu O
// contra fiecaruia din ceilalti, deci tot turneul ruleaza in paralel.
__global__ void kernelTurneu(const Individ* populatie, int* fitnessuri, int n) {

    int i = blockIdx.x * blockDim.x + threadIdx.x;
    int j = blockIdx.y * blockDim.y + threadIdx.y;

    if(i >= n || j >= n || i == j)
        return;

    int scoruri[2];
    joacaMeci(populatie[i], populatie[j], scoruri);

    atomicAdd(&fitnessuri[i], scoruri[0]);
    atomicAdd(&fitnessuri[j], scoruri[1]);
}

// Al doilea kernel: fiecare thread ia un individ si ii da meciuri contra unui jucator random.
__global__ void kernelContraRandom(const Individ* populatie, int* fitnessuri,
                                   int n, unsigned int seed) {

    int i = blockIdx.x * blockDim.x + threadIdx.x;

    if(i >= n)
        return;

    unsigned int stare = (seed + i * 747796405u) * 2891336453u | 1u;
    int total = 0;

    for(int m = 0; m < MECIURI_RANDOM; m++) {
        char simbolAI = (m % 2 == 0) ? 'X' : 'O';
        int rezultat = meciContraRandom(populatie[i], simbolAI, stare);

        if(rezultat == 1)
            total += 10;
        else if(rezultat == 0)
            total += 3;
    }

    fitnessuri[i] += total;
}

void evalueazaPopulatie(const vector<Individ>& populatie, vector<int>& fitnessuri) {

    int n = populatie.size();
    fitnessuri.assign(n, 0);

    Individ* dPopulatie;
    int* dFitnessuri;

    CUDA_OK(cudaMalloc(&dPopulatie, n * sizeof(Individ)));
    CUDA_OK(cudaMalloc(&dFitnessuri, n * sizeof(int)));

    CUDA_OK(cudaMemcpy(dPopulatie, populatie.data(),
                       n * sizeof(Individ), cudaMemcpyHostToDevice));
    CUDA_OK(cudaMemset(dFitnessuri, 0, n * sizeof(int)));

    dim3 bloc(16, 16);
    dim3 grila((n + 15) / 16, (n + 15) / 16);

    kernelTurneu<<<grila, bloc>>>(dPopulatie, dFitnessuri, n);
    kernelContraRandom<<<(n + 255) / 256, 256>>>(dPopulatie, dFitnessuri, n, rng());

    CUDA_OK(cudaGetLastError());
    CUDA_OK(cudaDeviceSynchronize());

    CUDA_OK(cudaMemcpy(fitnessuri.data(), dFitnessuri,
                       n * sizeof(int), cudaMemcpyDeviceToHost));

    cudaFree(dPopulatie);
    cudaFree(dFitnessuri);
}

int indexMaxim(const vector<int>& valori) {
    int best = 0;

    for(int i = 1; i < (int)valori.size(); i++) {
        if(valori[i] > valori[best])
            best = i;
    }

    return best;
}

void benchmarkContraRandom(const Individ& individ) {

    const int MECIURI = 1000;
    int victorii = 0, remize = 0, infrangeri = 0;
    unsigned int stare = rng() | 1;

    for(int m = 0; m < MECIURI; m++) {
        char simbolAI = (m % 2 == 0) ? 'X' : 'O';   // jumate din meciuri cu X, jumate cu O
        int rezultat = meciContraRandom(individ, simbolAI, stare);

        if(rezultat == 1)
            victorii++;
        else if(rezultat == 0)
            remize++;
        else
            infrangeri++;
    }

    cout << fixed << setprecision(1);
    cout << "Contra random: "
         << victorii * 100.0 / MECIURI << "% victorii, "
         << remize * 100.0 / MECIURI << "% remize, "
         << infrangeri * 100.0 / MECIURI << "% infrangeri\n";
}

// ==========================================
// ALGORITM GENETIC (pe CPU, e ieftin)
// ==========================================

// turneu: luam cativa indivizi la intamplare si il pastram pe cel mai bun
const Individ& selecteazaParinte(const vector<Individ>& populatie,
                                 const vector<int>& fitnessuri) {

    int castigator = intAleator(POP);

    for(int t = 1; t < TURNIR; t++) {
        int candidat = intAleator(POP);

        if(fitnessuri[candidat] > fitnessuri[castigator])
            castigator = candidat;
    }

    return populatie[castigator];
}

Individ crossover(const Individ& parinte1, const Individ& parinte2) {
    Individ copil;

    for(int i = 0; i < NR_PONDERI; i++) {
        if(intAleator(2))
            copil.p[i] = parinte1.p[i];
        else
            copil.p[i] = parinte2.p[i];
    }

    return copil;
}

Individ mutatie(Individ copil) {
    for(int i = 0; i < NR_PONDERI; i++) {
        if(aleator(0, 1) < RATA_MUTATIE)
            copil.p[i] += aleator(-PAS_MUTATIE, PAS_MUTATIE);
    }

    return copil;
}

// dupa apel, populatie[0] este cel mai bun individ din generatia anterioara (elitism)
int genereazaGeneratie(vector<Individ>& populatie) {

    vector<int> fitnessuri;
    evalueazaPopulatie(populatie, fitnessuri);

    int celMaiBun = indexMaxim(fitnessuri);
    int fitnessMaxim = fitnessuri[celMaiBun];

    vector<Individ> generatieNoua(POP);

    // pastram cel mai bun individ (elitism)
    generatieNoua[0] = populatie[celMaiBun];

    // cream restul generatiei
    for(int i = 1; i < POP; i++) {
        const Individ& parinte1 = selecteazaParinte(populatie, fitnessuri);
        const Individ& parinte2 = selecteazaParinte(populatie, fitnessuri);

        generatieNoua[i] = mutatie(crossover(parinte1, parinte2));
    }

    populatie = generatieNoua;

    return fitnessMaxim;
}

// ==========================================
// SALVARE SI INCARCARE (binar, e mult mai rapid decat text)
// ==========================================

bool salveazaPopulatie(const vector<Individ>& populatie, int generatie) {

    ofstream fisier(FISIER_SALVARE, ios::binary);

    if(!fisier)
        return false;

    int n = populatie.size();
    int nrPonderi = NR_PONDERI;

    fisier.write((const char*)&generatie, sizeof(int));
    fisier.write((const char*)&n, sizeof(int));
    fisier.write((const char*)&nrPonderi, sizeof(int));
    fisier.write((const char*)populatie.data(), n * sizeof(Individ));

    return (bool)fisier;
}

bool incarcaPopulatie(vector<Individ>& populatie, int& generatie) {

    ifstream fisier(FISIER_SALVARE, ios::binary);

    if(!fisier)
        return false;

    int n, nrPonderi;

    fisier.read((char*)&generatie, sizeof(int));
    fisier.read((char*)&n, sizeof(int));
    fisier.read((char*)&nrPonderi, sizeof(int));

    // salvarea trebuie sa fie facuta cu aceleasi setari ca programul curent
    if(!fisier || generatie < 0 || n != POP || nrPonderi != NR_PONDERI)
        return false;

    populatie.resize(n);
    fisier.read((char*)populatie.data(), n * sizeof(Individ));

    return (bool)fisier;
}

// ==========================================
// SPECTATOR
// ==========================================

void meciSpectator(const Individ& x, int idX, const Individ& o, int idO) {

    char tabla[3][3];
    golesteTabla(tabla);

    char jucator = 'X';

    while(true) {
        const Individ& individ = (jucator == 'X') ? x : o;

        int pozitie = mutareAI(tabla, individ, jucator);
        efectueazaMutare(tabla, pozitie / 3, pozitie % 3, jucator);

        afiseazaTabla(tabla);
        this_thread::sleep_for(chrono::milliseconds(250));

        if(verificaCastigator(tabla) != ' ' || tablaPlina(tabla))
            break;

        jucator = (jucator == 'X') ? 'O' : 'X';
    }

    char castigator = verificaCastigator(tabla);

    if(castigator == 'X')
        cout << "A castigat individul " << idX << " (X)!\n";
    else if(castigator == 'O')
        cout << "A castigat individul " << idO << " (O)!\n";
    else
        cout << "Remiza!\n";
}

void spectateaza(const vector<Individ>& populatie) {

    cout << "\nEvaluam populatia pentru a gasi cei mai buni indivizi...\n";

    vector<int> fitnessuri;
    evalueazaPopulatie(populatie, fitnessuri);

    int primul = 0;
    int alDoilea = 1;

    if(fitnessuri[alDoilea] > fitnessuri[primul])
        swap(primul, alDoilea);

    for(int i = 2; i < POP; i++) {

        if(fitnessuri[i] > fitnessuri[primul]) {
            alDoilea = primul;
            primul = i;
        }
        else if(fitnessuri[i] > fitnessuri[alDoilea]) {
            alDoilea = i;
        }
    }

    cout << "\nCei doi indivizi selectati:\n";
    cout << "Individul " << primul
         << " - Fitness: " << fitnessuri[primul] << endl;

    cout << "Individul " << alDoilea
         << " - Fitness: " << fitnessuri[alDoilea] << endl;

    cout << "\nPrimul meci: individul " << primul << " cu X\n";
    meciSpectator(populatie[primul], primul, populatie[alDoilea], alDoilea);

    cout << "\nAl doilea meci: rolurile inversate\n";
    meciSpectator(populatie[alDoilea], alDoilea, populatie[primul], primul);
}

// ==========================================
// JUCATOR CONTRA AI
// ==========================================

void joacaContraAI(const Individ& individ, char simbolOm) {

    char tabla[3][3];
    golesteTabla(tabla);

    char simbolAI = (simbolOm == 'X') ? 'O' : 'X';

    char jucator = 'X';
    bool jocTerminat = false;

    cout << "\nTu joci cu " << simbolOm << endl;
    cout << "AI-ul joaca cu " << simbolAI << endl;

    afiseazaTabla(tabla);

    while(!jocTerminat) {

        int pozitie;

        if(jucator == simbolOm) {

            cout << "Alege o pozitie (1-9): ";

            if(!(cin >> pozitie)) {
                if(cin.eof())
                    return;

                cin.clear();
                cin.ignore(numeric_limits<streamsize>::max(), '\n');
                cout << "Introdu un numar valid!\n";
                continue;
            }

            pozitie--;

            if(pozitie < 0 || pozitie > 8 ||
               !mutareValida(tabla, pozitie / 3, pozitie % 3)) {
                cout << "Pozitie invalida! Incearca din nou.\n";
                continue;
            }
        }
        else {
            cout << "AI-ul gandeste...\n";

            pozitie = mutareAI(tabla, individ, simbolAI);

            cout << "AI-ul a ales pozitia " << pozitie + 1 << endl;
        }

        efectueazaMutare(tabla, pozitie / 3, pozitie % 3, jucator);

        afiseazaTabla(tabla);

        if(verificaCastigator(tabla) != ' ' || tablaPlina(tabla))
            jocTerminat = true;
        else
            jucator = (jucator == 'X') ? 'O' : 'X';
    }

    char castigator = verificaCastigator(tabla);

    if(castigator == simbolOm)
        cout << "Felicitari! Ai castigat!\n";
    else if(castigator == simbolAI)
        cout << "AI-ul a castigat!\n";
    else
        cout << "Remiza!\n";
}

// ==========================================
// MENIUL PRINCIPAL
// ==========================================

int main() {

    int nrGpu = 0;

    if(cudaGetDeviceCount(&nrGpu) != cudaSuccess || nrGpu == 0) {
        cout << "Nu am gasit niciun GPU NVIDIA cu CUDA.\n";
        return 1;
    }

    cudaDeviceProp proprietati;
    CUDA_OK(cudaGetDeviceProperties(&proprietati, 0));
    cout << "GPU: " << proprietati.name << endl;

    vector<Individ> populatie;
    int generatie = 0;

    if(!incarcaPopulatie(populatie, generatie)) {
        cout << "Nu exista o salvare valida. Cream populatia initiala.\n";

        initializeazaPopulatie(populatie);
        generatie = 0;

        if(!salveazaPopulatie(populatie, generatie))
            cout << "Atentie: nu am putut salva populatia!\n";
    }
    else {
        cout << "Populatia a fost incarcata cu succes!\n";
        cout << "Generatia salvata: " << generatie << endl;
    }

    while(true) {

        cout << "\n";
        cout << "==============================\n";
        cout << "       TIC-TAC-TOE AI\n";
        cout << "==============================\n";
        cout << "Generatia curenta: " << generatie << endl;
        cout << "\n";

        cout << "1. Antreneaza AI-ul\n";
        cout << "2. Spectator (AI contra AI)\n";
        cout << "3. Joaca impotriva AI-ului\n";
        cout << "0. Iesire\n";

        cout << "\nAlege o optiune: ";

        int optiune;

        if(!(cin >> optiune)) {
            if(cin.eof())
                break;

            cin.clear();
            cin.ignore(numeric_limits<streamsize>::max(), '\n');
            cout << "Optiune invalida!\n";
            continue;
        }

        if(optiune == 0) {

            salveazaPopulatie(populatie, generatie);

            cout << "Progres salvat. La revedere!\n";
            break;
        }

        else if(optiune == 1) {

            int numarGeneratii;

            cout << "Cate generatii vrei sa antrenezi? ";

            if(!(cin >> numarGeneratii) || numarGeneratii <= 0) {
                cin.clear();
                cin.ignore(numeric_limits<streamsize>::max(), '\n');
                cout << "Numar invalid!\n";
                continue;
            }

            auto start = chrono::steady_clock::now();

            for(int g = 0; g < numarGeneratii; g++) {

                int fitnessMaxim = genereazaGeneratie(populatie);
                generatie++;

                // afisam si salvam la fiecare 10 generatii (si la ultima)
                if((g + 1) % 10 == 0 || g == numarGeneratii - 1) {

                    cout << "\nGeneratia " << generatie
                         << " - cel mai bun fitness: " << fitnessMaxim << endl;

                    benchmarkContraRandom(populatie[0]);

                    if(!salveazaPopulatie(populatie, generatie)) {
                        cout << "EROARE: progresul nu a putut fi salvat!\n";
                        break;
                    }
                }
            }

            chrono::duration<double> durata = chrono::steady_clock::now() - start;
            cout << "\nAntrenare terminata in " << durata.count() << " secunde.\n";
        }

        else if(optiune == 2) {

            spectateaza(populatie);
        }

        else if(optiune == 3) {

            cout << "\nEvaluam populatia pentru a alege AI-ul...\n";

            vector<int> fitnessuri;
            evalueazaPopulatie(populatie, fitnessuri);

            int celMaiBun = indexMaxim(fitnessuri);

            cout << "AI selectat: individul " << celMaiBun << endl;
            cout << "Fitness: " << fitnessuri[celMaiBun] << endl;

            char simbolOm;

            cout << "Vrei sa joci cu X sau O? ";
            cin >> simbolOm;

            simbolOm = toupper(simbolOm);

            if(simbolOm != 'X' && simbolOm != 'O') {
                cout << "Simbol invalid!\n";
                continue;
            }

            joacaContraAI(populatie[celMaiBun], simbolOm);
        }

        else {
            cout << "Optiune invalida!\n";
        }
    }

    return 0;
}
