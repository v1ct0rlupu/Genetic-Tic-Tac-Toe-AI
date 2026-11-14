#include <iostream>
#include <cstdlib>
#include <ctime>
#include <fstream>
#include <thread>
#include <chrono>
#include <iomanip>
#include <limits>
using namespace std;

struct Individ {
    float ponderi[9][9];
};

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

bool mutareValida(char tabla[3][3], int linie, int coloana) {
    if(linie < 0 || linie > 2 || coloana < 0 || coloana > 2)
        return false;

    if(tabla[linie][coloana] != ' ')
        return false;

    return true;
}

bool efectueazaMutare(char tabla[3][3], int linie, int coloana, char jucator) {
    if(!mutareValida(tabla, linie, coloana))
        return false;

    tabla[linie][coloana] = jucator;
    return true;
}

char verificaCastigator(char tabla[3][3]) {
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

bool tablaPlina(char tabla[3][3]) {
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

void transformaTabla(char tabla[3][3], int intrare[9], char simbol) {
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

float neuron(int intrare[], float ponderi[], int dimensiune) {
    float suma = 0;

    for(int i = 0; i < dimensiune; i++) {
        suma += intrare[i] * ponderi[i];
    }

    return suma;
}

void stratNeuronal(int intrare[9], float ponderi[9][9], float rezultate[9]) {
    for(int i = 0; i < 9; i++) {
        rezultate[i] = neuron(intrare, ponderi[i], 9);
    }
}

void relu(float rezultate[9]) {
    for(int i = 0; i < 9; i++) {
        if(rezultate[i] < 0)
            rezultate[i] = 0;
    }
}

int alegeMutare(float rezultate[9], char tabla[3][3]) {
    int pozitie = -1;
    float maxim = 0;

    for(int i = 0; i < 9; i++) {
        int linie = i / 3;
        int coloana = i % 3;

        if(tabla[linie][coloana] == ' ') {
            if(maxim < rezultate[i] || pozitie == -1) {
                maxim = rezultate[i];
                pozitie = i;
            }
        }
    }

    return pozitie;
}

int mutareAI(char tabla[3][3], Individ individ, char simbol) {
    int intrare[9];
    float rezultate[9];

    transformaTabla(tabla, intrare, simbol);
    stratNeuronal(intrare, individ.ponderi, rezultate);
    relu(rezultate);

    return alegeMutare(rezultate, tabla);
}

// ==========================================
// INITIALIZARE POPULATIE
// ==========================================

void initializeazaPopulatie(Individ populatie[100]) {
    for(int k = 0; k < 100; k++) {
        for(int i = 0; i < 9; i++) {
            for(int j = 0; j < 9; j++) {
                populatie[k].ponderi[i][j] =
                    (float)rand() / RAND_MAX * 2 - 1;
            }
        }
    }
}

// ==========================================
// FITNESS SI MECIURI
// ==========================================

int fitness(char tabla[3][3], char simbol) {
    if(verificaCastigator(tabla) == simbol)
        return 10;

    if(verificaCastigator(tabla) == ' ' && tablaPlina(tabla))
        return 3;

    return 0;
}

void joacaMeci(Individ individ1, Individ individ2,
               int scoruri[2], char simbol1, char simbol2,
               bool spectator = false) {

    char tabla[3][3];

    for(int i = 0; i < 3; i++) {
        for(int j = 0; j < 3; j++) {
            tabla[i][j] = ' ';
        }
    }

    char jucator = 'X';
    bool jocTerminat = false;

    while(!jocTerminat) {

        int pozitie;

        if(jucator == simbol1)
            pozitie = mutareAI(tabla, individ1, simbol1);
        else
            pozitie = mutareAI(tabla, individ2, simbol2);

        if(pozitie == -1)
            break;

        int linie = pozitie / 3;
        int coloana = pozitie % 3;

        efectueazaMutare(tabla, linie, coloana, jucator);

        if(spectator) {
            afiseazaTabla(tabla);
            this_thread::sleep_for(chrono::milliseconds(250));
        }

        if(verificaCastigator(tabla) != ' ')
            jocTerminat = true;
        else if(tablaPlina(tabla))
            jocTerminat = true;
        else {
            if(jucator == 'X')
                jucator = 'O';
            else
                jucator = 'X';
        }
    }

    scoruri[0] = fitness(tabla, simbol1);
    scoruri[1] = fitness(tabla, simbol2);
}

// ==========================================
// EVALUAREA POPULATIEI
// ==========================================

void evalueazaPopulatie(Individ populatie[100], int fitnessuri[100]) {

    for(int i = 0; i < 100; i++)
        fitnessuri[i] = 0;

    for(int i = 0; i < 100; i++) {
        for(int j = i + 1; j < 100; j++) {

            int scoruri1[2];
            int scoruri2[2];

            joacaMeci(populatie[i], populatie[j],
                      scoruri1, 'X', 'O');

            joacaMeci(populatie[i], populatie[j],
                      scoruri2, 'O', 'X');

            fitnessuri[i] += scoruri1[0] + scoruri2[0];
            fitnessuri[j] += scoruri1[1] + scoruri2[1];
        }
    }
}

// ==========================================
// ALGORITM GENETIC
// ==========================================

Individ selecteazaParinte(Individ populatie[100],
                          int fitnessuri[100], int a, int b) {

    if(fitnessuri[a] > fitnessuri[b])
        return populatie[a];

    if(fitnessuri[b] > fitnessuri[a])
        return populatie[b];

    if(rand() % 2)
        return populatie[a];

    return populatie[b];
}

Individ crossover(Individ parinte1, Individ parinte2) {
    Individ copil;

    for(int i = 0; i < 9; i++) {
        for(int j = 0; j < 9; j++) {
            if(rand() % 2)
                copil.ponderi[i][j] = parinte1.ponderi[i][j];
            else
                copil.ponderi[i][j] = parinte2.ponderi[i][j];
        }
    }

    return copil;
}

Individ mutatie(Individ copil) {
    for(int i = 0; i < 9; i++) {
        for(int j = 0; j < 9; j++) {
            if(rand() % 100 < 5) {
                copil.ponderi[i][j] +=
                    (float)rand() / RAND_MAX * 0.4 - 0.2;
            }
        }
    }

    return copil;
}

int genereazaGeneratie(Individ populatie[100],
                       Individ generatieNoua[100]) {

    int fitnessuri[100];

    evalueazaPopulatie(populatie, fitnessuri);

    // Gasim cel mai bun individ
    int celMaiBun = 0;

    for(int i = 1; i < 100; i++) {
        if(fitnessuri[i] > fitnessuri[celMaiBun])
            celMaiBun = i;
    }

    int fitnessMaxim = fitnessuri[celMaiBun];

    // Pastram cel mai bun individ (elitism)
    generatieNoua[0] = populatie[celMaiBun];

    // Cream restul generatiei
    for(int i = 1; i < 100; i++) {

        int a = rand() % 100;
        int b = rand() % 100;

        int c = rand() % 100;
        int d = rand() % 100;

        Individ parinte1 = selecteazaParinte(
            populatie, fitnessuri, a, b
        );

        Individ parinte2 = selecteazaParinte(
            populatie, fitnessuri, c, d
        );

        Individ copil = crossover(parinte1, parinte2);

        generatieNoua[i] = mutatie(copil);
    }

    return fitnessMaxim;
}

// ==========================================
// SALVARE SI INCARCARE
// ==========================================

bool salveazaPopulatie(Individ populatie[100], int generatie) {

    ofstream fisier("populatie.txt");

    if(!fisier)
        return false;

    fisier << setprecision(9);
    fisier << generatie << endl;

    for(int k = 0; k < 100; k++) {
        for(int i = 0; i < 9; i++) {
            for(int j = 0; j < 9; j++) {
                fisier << populatie[k].ponderi[i][j] << endl;
            }
        }
    }

    fisier.close();

    return !fisier.fail();
}

bool incarcaPopulatie(Individ populatie[100], int &generatie) {

    ifstream fisier("populatie.txt");

    if(!fisier)
        return false;

    fisier >> generatie;

    if(!fisier || generatie < 0)
        return false;

    for(int k = 0; k < 100; k++) {
        for(int i = 0; i < 9; i++) {
            for(int j = 0; j < 9; j++) {

                fisier >> populatie[k].ponderi[i][j];

                if(!fisier)
                    return false;
            }
        }
    }

    fisier.close();
    return true;
}

// ==========================================
// SPECTATOR
// ==========================================

void spectateaza(Individ populatie[100]) {

    cout << "\nEvaluam populatia pentru a gasi cei mai buni indivizi...\n";

    int fitnessuri[100];
    evalueazaPopulatie(populatie, fitnessuri);

    int primul = 0;
    int alDoilea = 1;

    if(fitnessuri[alDoilea] > fitnessuri[primul])
        swap(primul, alDoilea);

    for(int i = 2; i < 100; i++) {

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

    int scoruri[2];

    cout << "\nPrimul meci: X contra O\n";

    joacaMeci(populatie[primul], populatie[alDoilea],
              scoruri, 'X', 'O', true);

    if(scoruri[0] > scoruri[1])
        cout << "A castigat individul " << primul << "!\n";
    else if(scoruri[1] > scoruri[0])
        cout << "A castigat individul " << alDoilea << "!\n";
    else
        cout << "Remiza!\n";

    cout << "\nAl doilea meci: rolurile inversate\n";

    joacaMeci(populatie[primul], populatie[alDoilea],
              scoruri, 'O', 'X', true);

    if(scoruri[0] > scoruri[1])
        cout << "A castigat individul " << primul << "!\n";
    else if(scoruri[1] > scoruri[0])
        cout << "A castigat individul " << alDoilea << "!\n";
    else
        cout << "Remiza!\n";
}

// ==========================================
// JUCATOR CONTRA AI
// ==========================================

void joacaContraAI(Individ individ, char simbolOm) {

    char tabla[3][3];

    for(int i = 0; i < 3; i++) {
        for(int j = 0; j < 3; j++) {
            tabla[i][j] = ' ';
        }
    }

    char simbolAI;

    if(simbolOm == 'X')
        simbolAI = 'O';
    else
        simbolAI = 'X';

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

            if(pozitie == -1)
                break;

            cout << "AI-ul a ales pozitia " << pozitie + 1 << endl;
        }

        int linie = pozitie / 3;
        int coloana = pozitie % 3;

        efectueazaMutare(tabla, linie, coloana, jucator);

        afiseazaTabla(tabla);

        if(verificaCastigator(tabla) != ' ') {
            jocTerminat = true;
        }
        else if(tablaPlina(tabla)) {
            jocTerminat = true;
        }
        else {
            if(jucator == 'X')
                jucator = 'O';
            else
                jucator = 'X';
        }
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

    srand(time(0));

    Individ populatie[100];
    Individ generatieNoua[100];

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

            for(int g = 0; g < numarGeneratii; g++) {

                cout << "\nAntrenam generatia "
                     << generatie + 1 << "...\n";

                int fitnessMaxim =
                    genereazaGeneratie(populatie, generatieNoua);

                for(int i = 0; i < 100; i++) {
                    populatie[i] = generatieNoua[i];
                }

                generatie++;

                if(!salveazaPopulatie(populatie, generatie)) {
                    cout << "EROARE: progresul nu a putut fi salvat!\n";
                    break;
                }

                cout << "Generatia " << generatie
                     << " terminata!\n";

                cout << "Cel mai bun fitness: "
                     << fitnessMaxim << endl;

                cout << "Progres salvat.\n";
            }
        }

        else if(optiune == 2) {

            spectateaza(populatie);
        }

        else if(optiune == 3) {

            cout << "\nEvaluam populatia pentru a alege AI-ul...\n";

            int fitnessuri[100];
            evalueazaPopulatie(populatie, fitnessuri);

            int celMaiBun = 0;

            for(int i = 1; i < 100; i++) {
                if(fitnessuri[i] > fitnessuri[celMaiBun])
                    celMaiBun = i;
            }

            cout << "AI selectat: individul " << celMaiBun << endl;
            cout << "Fitness: " << fitnessuri[celMaiBun] << endl;

            char simbolOm;

            cout << "Vrei sa joci cu X sau O? ";
            cin >> simbolOm;

            if(simbolOm == 'x')
                simbolOm = 'X';

            if(simbolOm == 'o')
                simbolOm = 'O';

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
