#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <iostream>
#include <cuda.h>
#include <cuda_runtime.h>
#include <curand_kernel.h>
#include <time.h>
#include <windows.h>
#include <conio.h>  // Para _kbhit() y _getch()
#include <crt/device_functions.h>
#include <locale>
/*#include <GL\glew.h>
#include <GLFW\glfw3.h>*/

#include <string>

using namespace std;

//Declaración de variables y constantes globales en la CPU (a las constantes se permite acceso desde la GPU):
short filas = 20;
short columnas = 15;
short dimTablero = 0;
short vidas = 5;
short puntos = 0;
short pasos = 0;
short posicionNave = (int)(columnas / 2);
boolean modoAuto = true;
boolean impacto = false;
//char mensaje[];
const short filaBloques = 6; //es decir la 5ª fila empezando por el final

const short pausaInicioJuego = 3000;

const short retardoInicial = 1000;
short retardo = retardoInicial;
const short incrementoAceleracion = 20; //es el % que se va a acelerar el juego cada vez que desciendas un nº de "filas" filas.

const short maxBloquesSeguidos = 3;

//Constantes para requisitos de número de columnas y filas:
const short minColumnas = 10;
const short minFilas = 15;

//Constantes de probabilidades (%) de generación de los bichos:
const short porcA = 40;
const short porcN = 65;
const short porcC = 80;
const short porcD = 85;
const short porcR = 98;
//const short porcX = 100;

//Constantes de probabilidades de generación de bloques:
const short porcBloque = 15;

//Constantes de letras de los bichos y resto de elementos:
const char letraA = 'A';
const char letraN = 'N';
const char letraC = 'C';
const char letraD = 'D';
const char letraR = 'R';
const char letraX = 'X';
const char hueco = ' ';
const char letraBloque = 'B';
const char letraNave = 'W';


// Esta función la hago para inicializar la matriz con valores aleatorios con las condiciones 
// que nos dió Lorena:
__global__ void inicializarMatriz(char* matriz, curandState* state, short* dev_posicionNave, short* d_filas, short* d_columnas) {
    short fila = blockIdx.x;
    short indice = threadIdx.x + fila * blockDim.x;
    curand_init(clock64(), indice, 0, &state[indice]);  // Inicializo la semilla con un valor único
    curandState localState = state[indice];  // Obtengo el estado de curand local para este hilo

    short filas = *d_filas;
    short columnas = *d_columnas;

    // Ponemos todas las celdas a vacío:
    for (short i = 1; i < filas; ++i) {
        for (short j = 0; j < columnas; ++j) {
            matriz[i * columnas + j] = hueco;
            if (i == filas - 1) {
                matriz[i * columnas + j] = '_';
            }
        }
    }

    // Creamos los alienígenas:
    // Este array aleatorio[] es para asegurarnos que varios hilos no cogen el mismo valor aleatorio.
    // Colocamos cada número aleatorio en su posición: 
    //const short col = columnas;

    //ponemos extern para que nos deje definir la constante
    extern __shared__ short aleatorio[];
    for (short j = 0; j < columnas; ++j) {
        aleatorio[j] = (int)(curand_uniform(&localState) * 100);
        if (aleatorio[j] < porcA) { //Alienígena
            matriz[j] = letraA;
        }
        else if (aleatorio[j] < porcN) { //Nube
            matriz[j] = letraN;
        }
        else if (aleatorio[j] < porcC) { //Cefalópodo
            matriz[j] = letraC;
        }
        else if (aleatorio[j] < porcD) { //Destructor
            matriz[j] = letraD;
        }
        else if (aleatorio[j] < porcR) { //Crucero
            matriz[j] = letraR;
        }
        else { //Comandante
            matriz[j] = letraX;
        }
    }
        
    // Creamos los obstáculos, tirando el dado aleatorio. Si está dentro del 15%, miro sus 3 celdas adjuntas a cada lado:    
    for (short j = 0; j < columnas; ++j) {
        // Si hay menos de 3 obstáculos consecutivos, colocar un obstáculo
        aleatorio[j] = (int)(curand_uniform(&localState) * 100);
        if (aleatorio[j] < porcBloque) {
            //compruebo las maxBloquesSeguidos posiciones antes y maxBloquesSeguidos después, contando:
            short bloquesIzqda = 0;
            short bloquesDcha = 0;
            for (short k = j - 1; k >= j - maxBloquesSeguidos; k--) {
                if (k>=0 && matriz[(filas - filaBloques) * columnas + k] == letraBloque) {
                    bloquesIzqda++;
                }
                else { //Si es un hueco dejo de contar
                    break;
                }
            }
            for (short k = j + 1; k >= j + maxBloquesSeguidos; k++) {
                if (k<columnas && matriz[(filas - filaBloques) * columnas + k] == letraBloque) {
                    bloquesDcha++;
                }
                else { //Si es un hueco dejo de contar
                    break;
                }
            }

            //Si los bloques a derecha e izquierda suman menos que el máximo, puede ser bloque. Si no, hueco:
            if (bloquesIzqda + bloquesDcha < maxBloquesSeguidos) {
                matriz[(filas - filaBloques) * columnas + j] = letraBloque;
            }
            else {
                matriz[(filas - filaBloques) * columnas + j] = hueco;
            }

        }

        // Creamos la nave terrícola en la celda central de la última fila:
        matriz[(filas - 1) * columnas + *dev_posicionNave] = letraNave;
    }

}


// Con esta función Función para imprimo la matriz:
void imprimirEscenario(const char* matriz) {

    //d::cout << "\033[1;31mTexto en rojo\033[0m" << std::endl;
    printf("Estado inicial:\n");

    system("cls");
    printf("Paso %d:\n", pasos);

    //Límite superior del escenario:
    printf("%c-", '|');
    for (short j = 0; j < columnas; ++j) {
        printf("-%c-", '-');
    }
    printf("-%c", '|');
    printf("\n");

    //Pinto fila a fila:
    for (short i = 0; i < filas - 1; ++i) {
        // límite lateral izquierdo:
        printf("%c ", '|');

        // contenido de la fila:
        for (short j = 0; j < columnas; ++j) {
            if (matriz[i * columnas + j] == letraA) {
                printf("\033[1;32m %c \033[0m", matriz[i * columnas + j]);
            }
            else if (matriz[i * columnas + j] == letraN) {
                printf("\033[38;5;208m %c \033[0m", matriz[i * columnas + j]);
            }
            else if (matriz[i * columnas + j] == letraC) {
                printf("\033[1;34m %c \033[0m", matriz[i * columnas + j]);
            }
            else if (matriz[i * columnas + j] == letraD) {
                printf("\033[38;5;198m %c \033[0m", matriz[i * columnas + j]);
            }
            else if (matriz[i * columnas + j] == letraR) {
                printf("\033[1;33m %c \033[0m", matriz[i * columnas + j]);
            }
            else if (matriz[i * columnas + j] == letraX) {
                printf("\033[1;31m %c \033[0m", matriz[i * columnas + j]);
            }
            else if (matriz[i * columnas + j] == letraBloque) {
                printf("*%c*", matriz[i * columnas + j]);
            }
            else {
                printf(" %c ", matriz[i * columnas + j]);
            }

        }
        // límite lateral derecho:
        printf(" %c", '|');
        printf("\n");
    }

    //Fila de la tierra (inferior):
    printf("%c_", '|');
    for (short j = 0; j < columnas; ++j) {
        if (j == posicionNave) {
            printf("_%c_", matriz[(filas - 1) * columnas + j]);
        }
        else {
            printf("_%c_", '_');
        }
    }
    printf("_%c", '|');
    printf("\n");

}

// Función para imprimir las vidas, los puntos, etc
void imprimirMarcador() {
    printf("%s", "\nVidas restantes: ");
    printf("%i", vidas);
    printf("%s", "\t");
    printf("%s", "Puntos: ");
    printf("%i", puntos);
    printf("%s", "\n");    
    if (modoAuto) {
        float porcentajeRetardo = (float)(retardoInicial - retardo) / retardoInicial * 100.0f;        
        printf("Velocidad: %i%%\n", (short)(100 + porcentajeRetardo));
    }
}

// Función para pausar el programa durante una cantidad de milisegundos
void delay(int milliseconds) {
    clock_t start_time = clock();
    while (clock() < start_time + milliseconds);
}

__global__ void crearAlienigenas(char* dev_matriz, curandState* state, short* d_filas, short* d_columnas) {
    short indice = threadIdx.x + blockIdx.x * blockDim.x;
    curand_init(clock64(), indice, 0, &state[indice]);  // Inicializar la semilla con un valor único
    curandState localState = state[indice];  // Obtener el estado de curand local para este hilo

    short filas = *d_filas;
    short columnas = *d_columnas;

    // Defino el tamaño de la memoria compartida dinámicamente:
    //static short col = columnas;
    extern __shared__ short aleatorio[];
    // Creamos los alienígenas conforme los requisitos del enunciado:
    for (short j = 0; j < columnas; ++j) {
        aleatorio[j] = (int)(curand_uniform(&localState) * 100);
        //printf("%i ", aleatorio);        
        if (aleatorio[j] < porcA) { //Alienígena
            dev_matriz[j] = letraA;
        }
        else if (aleatorio[j] < porcN) { //Nube
            dev_matriz[j] = 'N';
        }
        else if (aleatorio[j] < porcC) { //Cefalópodo
            dev_matriz[j] = letraC;
        }
        else if (aleatorio[j] < porcD) { //Destructor
            dev_matriz[j] = letraD;
        }
        else if (aleatorio[j] < porcR) { //Crucero
            dev_matriz[j] = letraR;
        }
        else { //Comandante
            dev_matriz[j] = letraX;
        }
    }
    __syncthreads();
}


/* Voy a llamar al kernel "descensoYDesintegracion", y lo pongo como "global" para que sea accesible tanto
    para la GPU como para la CPU */
__global__ void descensoYDesintegracion(char* dev_matriz, curandState* state, short* d_filas, short* d_columnas) {
    // Índice linealizado:
    short indice = threadIdx.x + blockIdx.x * blockDim.x;  
    short filas = *d_filas;
    short columnas = *d_columnas;

    if (indice < filas * columnas) {  // Verifico límite de índice
        short filaActual = indice / columnas;  // Calculo la fila actual
        short filaSiguiente = filaActual + 1;

        // Movimiento de las celdas de bichos a la siguiente fila, excluyo la última fila (la de tierra)
        if (filaActual < filas - 1) {
            char actual = dev_matriz[indice];
            char siguiente = dev_matriz[indice + columnas];

            if (actual == letraA || actual == letraN || actual == hueco ||
                actual == letraC || actual == letraD || actual == letraR || actual == letraX) {
                if (siguiente == letraBloque &&
                    (actual == letraA || actual == hueco || actual == letraN || actual == letraC || actual == letraD)) {
                    // Manejo de explosión para letraD
                    if (actual == letraD) {
                        const short radio = 5;
                        for (short i = -radio; i <= radio; ++i) {
                            for (short k = -radio; k <= radio; ++k) {
                                short nuevaFila = filaActual + i;
                                short nuevaColumna = (indice % columnas) + k;
                                if (nuevaFila >= 0 && nuevaFila < filas && nuevaColumna >= 0 && nuevaColumna < columnas) {
                                    if (dev_matriz[nuevaFila * columnas + nuevaColumna] != letraBloque) {
                                        dev_matriz[nuevaFila * columnas + nuevaColumna] = hueco;
                                    }
                                }
                            }
                        }
                    }
                    dev_matriz[(filaSiguiente * columnas) + (indice % columnas)] = letraBloque;
                }
                else if (siguiente == letraBloque &&
                    (actual == letraR || actual == letraX)) {
                    dev_matriz[(filaSiguiente * columnas) + (indice % columnas)] = hueco;
                    // Manejo de destrucción de bichos para letraR
                    if (actual == letraR) {
                        curandState localState = state[indice];
                        short queDestruyo = curand_uniform(&localState) < 0.5 ? 0 : 1;
                        if (queDestruyo == 0) { // Destruir fila
                            short inicio = filaActual * columnas;
                            short fin = inicio + columnas;
                            for (short i = inicio; i < fin; ++i) {
                                if (dev_matriz[i] != letraBloque && dev_matriz[i] != letraNave) {
                                    dev_matriz[i] = hueco;
                                }
                            }
                        }
                        else { // Destruir columna
                            for (short i = indice % columnas; i < (filas - 1) * columnas; i += columnas) {
                                if (dev_matriz[i] != letraNave && dev_matriz[i] != letraBloque) {
                                    dev_matriz[i] = hueco;
                                }
                            }
                        }
                    }
                }
                else {
                    dev_matriz[(filaSiguiente * columnas) + (indice % columnas)] = actual;
                }
            }
        }
    }
}


__global__ void reconvertir_nube(char* matriz, short* d_filas, short* d_columnas) {
    int fila = blockIdx.x;
    int columna = threadIdx.x;
    bool adyacentes = false;

    short filas = *d_filas;
    short columnas = *d_columnas;

    // Calcula el índice de la celda actual
    int indice = fila * columnas + columna;

    // Comprueba si la celda actual contiene letraA
    if (matriz[indice] == letraA) {
        // Verifica si todas las celdas adyacentes son letraA
            
            adyacentes = (matriz[indice - columnas] == letraA) && // Arriba
            (matriz[indice + columnas] == letraA) && // Abajo
            (matriz[fila * columnas + (columna - 1)] == letraA) && // Izquierda
            (matriz[fila * columnas + (columna + 1)] == letraA); // Derecha

            if (adyacentes) matriz[indice] = letraN; // Transforma la celda actual en letraN

    }
    
// Si todas las celdas adyacentes son letraA, transforma la celda actual y las adyacentes
        if (adyacentes) {

           if (matriz[indice - columnas] ==letraA) matriz[indice - columnas] = hueco; // Arriba
           if (matriz[indice + columnas] == letraA) matriz[indice + columnas] = hueco; // Abajo
           if (matriz[fila * columnas + (columna - 1)] == letraA) matriz[fila * columnas + (columna - 1)] = hueco; // Izquierda
           if (matriz[fila * columnas + (columna + 1)] == letraA) matriz[fila * columnas + (columna + 1)] = hueco; // Derecha
        }
        __syncthreads();
}

__global__ void reconvertir_cefalopodo(char* matriz, short* d_filas, short* d_columnas) {
    int fila = blockIdx.x;
    int columna = threadIdx.x;
    bool adyacentes = false;

    short filas = *d_filas-1;
    short columnas = *d_columnas;


    // Calcula el índice de la celda actual
    int indice = fila * columnas + columna;

    // Comprueba si la celda actual contiene letraN
    if (matriz[indice] == letraN) {
        // Verifica si todas las celdas adyacentes son letraA
        adyacentes = (matriz[indice-columnas] == letraA) && // Arriba
            (matriz[indice + columnas] == letraA) && // Abajo
            (matriz[fila * columnas + (columna - 1)] == letraA) && // Izquierda
            (matriz[fila * columnas + (columna + 1)] == letraA); // Derecha

    }
    

// Si todas las celdas adyacentes son letraA, transforma la celda actual y las adyacentes
        if (adyacentes) {

            matriz[indice] = letraC; // Transforma la celda actual en letraC
            matriz[indice - columnas] = hueco; // Arriba
            matriz[indice + columnas] = hueco; // Abajo
            matriz[fila * columnas + (columna - 1)] = hueco; // Izquierda
            matriz[fila * columnas + (columna + 1)] = hueco; // Derecha
        }
        __syncthreads();
}




__global__ void reconvertir_comandante(char* matriz, curandState* state, short* d_filas, short* d_columnas) {
    int fila = blockIdx.x;
    int columna = threadIdx.x;

    short filas = *d_filas-1;
    short columnas = *d_columnas;

    // Calcula el índice de la celda actual
    int indice = fila * columnas + columna;

    // Comprueba si la celda actual contiene letraX
    if (matriz[indice] == letraX) {

        curandState localState = state[fila * columnas + columna]; // Obtener el estado de curand local para este hilo

        short generar_nubes = curand_uniform(&localState) < 0.26 ? 0 : 1;

        if (generar_nubes == 0) {

            if (fila > 0) matriz[(fila - 1) * columnas + columna] = letraN; // Arriba
            if (fila < filas - 1) matriz[(fila + 1) * columnas + columna] = letraN; // Abajo
            if (columna > 0) matriz[fila * columnas + (columna - 1)] = letraN; // Izquierda
            if (columna < columnas - 1) matriz[fila * columnas + (columna + 1)] = letraN; // Derecha

        }
    }
    __syncthreads();
}


__global__ void comprobarSuelo(char* dev_matriz, curandState* state, short* dev_posicionNave, short* dev_vidas, short* dev_puntos, short* d_filas, short* d_columnas) {

    short filas = *d_filas;
    short columnas = *d_columnas;

    short filaSuelo = filas - 1;
    for (short j = 0; j < columnas; ++j) {
        if (dev_matriz[(filaSuelo)*columnas + j] == letraA ||
            dev_matriz[(filaSuelo)*columnas + j] == letraN ||
            dev_matriz[(filaSuelo)*columnas + j] == letraC ||
            dev_matriz[(filaSuelo)*columnas + j] == letraD ||
            dev_matriz[(filaSuelo)*columnas + j] == letraR ||
            dev_matriz[(filaSuelo)*columnas + j] == letraX) {
            if (*dev_posicionNave == j) {
                *dev_vidas -= 1;
            }

            //Comprobamos si la fila es la del suelo, si lo es compruebo acciones: puntos, vidas y explosiones:
            if (dev_matriz[(filaSuelo)*columnas + j] == letraA) {
                *dev_puntos += 5;
            }
            else if (dev_matriz[(filaSuelo)*columnas + j] == letraN) {
                *dev_puntos += 25;
            }
            else if (dev_matriz[(filaSuelo)*columnas + j] == letraC) {
                *dev_puntos += 15;
            }
            else if (dev_matriz[(filaSuelo)*columnas + j] == letraD) {
                *dev_puntos += 5;
                // onda_expansiva << <filaSuelo, columnas >> > (d_matriz, "D", (filaSuelo) * columnas + j);
                // Requisito: si el bicho es un destructor, destruye todos los bichos en unn radio de 5 celdas.
                // radio alrededor de la posición actual:
                const short radio = 5;

                // Recorro las celdas dentro del radio y les asigno el valor hueco:
                for (short i = -radio; i <= radio; ++i) {
                    for (short k = -radio; k <= radio; ++k) {
                        // Calculo las nuevas coordenadas de la celda
                        short nuevaFila = (filaSuelo)+i;
                        short nuevaColumna = j + k;

                        // Verifico si las nuevas coordenadas están dentro de los límites de la matriz:
                        if (nuevaFila >= 0 && nuevaFila < filas && nuevaColumna >= 0 && nuevaColumna < columnas) {
                            // Asigno el valor hueco a la celda en las nuevas coordenadas:
                            dev_matriz[nuevaFila * columnas + nuevaColumna] = hueco;
                        }
                    }
                }
                //Requisito: si la nave terrícola está en el radio de la explosión, pierdo una vida:
                if (abs(*dev_posicionNave - j) <= radio) {
                    *dev_vidas -= 1;
                }
            }
            else if (dev_matriz[(filaSuelo)*columnas + j] == letraR) {
                *dev_puntos += 13;
                // Generar un número aleatorio entre 0 y 1 para decidir si destruyo los bichos de la fila o de la columna
                curandState localState = state[filaSuelo * columnas + j];
                short queDestruyo = curand_uniform(&localState) < 0.5 ? 0 : 1;

                if (queDestruyo == 0) { //destruyo la fila:
                    for (short k = 0; k < columnas; ++k) {
                        if (dev_matriz[filaSuelo * columnas + k] != letraBloque && dev_matriz[filaSuelo * columnas + k] != letraNave) {
                            dev_matriz[filaSuelo * columnas + k] = hueco;
                        }
                    }
                }
                else { //destruyo la columna:
                    for (short i = 0; i < filas - 1; ++i) {
                        if (dev_matriz[i * columnas + j] != letraNave && dev_matriz[i * columnas + j] != letraBloque) {
                            dev_matriz[i * columnas + j] = hueco;
                        }
                    }
                }
            }
            else if (dev_matriz[(filaSuelo)*columnas + j] == letraX) {
                *dev_puntos += 100;
                *dev_vidas += 1;
            }
        }
    }

    // Vuelvo a poner la fila final (la de tierra) con los valores de tierra
    for (short j = 0; j < columnas; ++j) {
        if (*dev_posicionNave == j) {
            dev_matriz[(filaSuelo)*columnas + j] = letraNave;
        }
        else {
            dev_matriz[(filaSuelo)*columnas + j] = '_';
        }
    }
    __syncthreads();
}



void leerModoYDimensiones(int argc, char* argv[]) {

    string modo = "";
    int numColumnas = 0;
    int numFilas = 0;

    // Verifico si se proporcionaron los 3 argumentos necesarios. Si no, los pido por consola:
    if (argc < 4) { // CONSOLA:
        do {
            cout << "Dame el modo de ejecución (-m para manual, -a para automático): ";
            cin >> modo;
        } while (modo != "-m" && modo != "-a");
        // Controlamos que el número de filas y columnas cumplan el mínimo y que sea irregular, tal como nos piden en el enunciado:
        do {
            do {
                cout << "Dame un número de columnas mayor que " << minColumnas << ": ";
                cin >> numColumnas;
            } while (numColumnas < minColumnas);
            do {
                cout << "Dame un número de filas mayor que " << minFilas << ": ";
                cin >> numFilas;
            } while (numFilas < minFilas);
        } while (numFilas <= numColumnas);
    }
    else { //ARGUMENTOS. Los leemos y valoramos si son válidos.
        modo = argv[1];
        if (modo != "-m" && modo != "-a") {
            cout << "Parámetro Modo no válido." << endl;
            do {
                cout << "Dame el modo de ejecución (-m para manual, -a para automático): ";
                cin >> modo;
            } while (modo != "-m" && modo != "-a");
        }
        numColumnas = atoi(argv[2]);
        numFilas = atoi(argv[3]);
        // Controlamos que el número de filas y columnas cumplan el mínimo y que sea irregular, tal como nos piden en el enunciado:
        if (numColumnas < minColumnas || numFilas < minFilas || numFilas <= numColumnas) {
            cout << "Parámetros Columnas y Filas no válidos." << endl;
            do {
                do {
                    cout << "Dame un número de columnas mayor que " << minColumnas << ": ";
                    cin >> numColumnas;
                } while (numColumnas < minColumnas);
                do {
                    cout << "Dame un número de filas mayor que " << minFilas << ": ";
                    cin >> numFilas;
                } while (numFilas < minFilas);
            } while (numFilas <= numColumnas);
        }

    }

    //Finalmente, inicializamos las variables globales con los datos correctos leídos:
    modoAuto = (modo=="-m"?false:true);
    filas = numFilas;
    columnas = numColumnas;
    dimTablero = filas * columnas;

}

void leerMovimiento() {

    char tecla;
    bool teclaValida = false;
    while (!teclaValida) {
        if (_kbhit()) { // Verifico si hay una tecla presionada
            tecla = _getch(); // Obtener la tecla presionada
            if (tecla == 77) { // flecha derecha en código ASCII=77
                // Muevo la nave hacia la derecha e incremento la posición de la nave
                if (posicionNave < columnas - 1) { // Verifico si la posición está dentro de los límites
                    posicionNave++;
                    teclaValida = true;
                }
            }
            else if (tecla == 75) { // flecha izquierda en codigo ASCII=75
                // Muevo la nave hacia la izquierda y decremento la posición de la nave
                if (posicionNave > 0) { // Verifico si la posición está dentro de los límites
                    posicionNave--;
                    teclaValida = true;
                }
            }
            else if (tecla == 72 || tecla == 80) { // flecha arriba o abajo en codigo ASCII
                // Nos quedamos donde estamos:
                teclaValida = true;
            }
        }
    }
}

void generarMovimiento() {
    srand(time(0));

    short direccion = rand() % 2;  // 0 para izquierda, 1 para derecha

    if (direccion == 0 && posicionNave > 0) { // Mover hacia la izquierda si es posible
        posicionNave--;
    }
    else if (direccion == 1 && posicionNave < columnas - 1) { // Mover hacia la derecha si es posible
        posicionNave++;
    }
}


int main(int argc, char* argv[]) {

    //Lo primero cargo UTF-8:
    std::locale::global(std::locale(""));

    leerModoYDimensiones(argc, argv);       

    // Creamos las variables que vamos a enviar a la GPU, gemelas de las variables de la CPU:    
    char* h_matriz = (char*)malloc(filas * columnas * sizeof(char));
    char* d_matriz; //gemela de h_matriz
    short* d_vidas;
    short* d_puntos;
    short* d_posicionNave;
    short* d_filas;
    short* d_columnas;
    //char* d_mensaje;

    dim3 dimGrid(1);
    dim3 dimBlock(dimTablero);

    curandState* d_state; // matriz para los estados de curand (aleatoriedad)

    //Reservo memoria en la GPU para cada variable de device:
    cudaMalloc(&d_matriz, filas * columnas * sizeof(char));
    cudaMalloc(&d_state, filas * columnas * sizeof(curandState));
    cudaMalloc((void**)&d_vidas, sizeof(short));
    cudaMalloc((void**)&d_puntos, sizeof(short));
    cudaMalloc((void**)&d_posicionNave, sizeof(short));
    cudaMalloc((void**)&d_filas, sizeof(short));
    cudaMalloc((void**)&d_columnas, sizeof(short));

    //Mando a la GPU el valor de posicionNave a d_posicionNave
    cudaMemcpy(d_posicionNave, &posicionNave, sizeof(short), cudaMemcpyHostToDevice);    
    cudaMemcpy(d_filas, &filas, sizeof(short), cudaMemcpyHostToDevice);
    cudaMemcpy(d_columnas, &columnas, sizeof(short), cudaMemcpyHostToDevice);


    // Llamo al kernel de inicialización:
    inicializarMatriz << <dimGrid, dimBlock >> > (d_matriz, d_state, d_posicionNave, d_filas, d_columnas);

    cudaMemcpy(h_matriz, d_matriz, filas * columnas * sizeof(char), cudaMemcpyDeviceToHost);

    delay(pausaInicioJuego*2);

    //Imprimo la matriz del juego y los marcadores:
    imprimirEscenario(h_matriz);
    imprimirMarcador();

    if (modoAuto) { // Pausa inicial si estamos como auto
        delay(pausaInicioJuego);
    }

    while (true) { //Este while true no le gustó a Lorena pero se lo explicamos

        if (!modoAuto) {
            leerMovimiento();            
        }
        else {
            generarMovimiento();            
            delay(retardo);
        }

        // Copiamos a Device:
        cudaMemcpy(d_vidas, &vidas, sizeof(short), cudaMemcpyHostToDevice);
        cudaMemcpy(d_puntos, &puntos, sizeof(short), cudaMemcpyHostToDevice);
        cudaMemcpy(d_posicionNave, &posicionNave, sizeof(short), cudaMemcpyHostToDevice);

        // Respetamos el orden que nos piden en el enunciado. 
        // Ojo: pasamos por parámetro a todos los kernel las dimensiones de la matriz (filas y columnas) porque ya no son constantes globales, sino variables globales.
        reconvertir_cefalopodo << < dimGrid, dimBlock >> > (d_matriz, d_filas, d_columnas);
        reconvertir_nube << < dimGrid, dimBlock >> > (d_matriz, d_filas, d_columnas);
        reconvertir_comandante << < dimGrid, dimBlock >> > (d_matriz, d_state, d_filas, d_columnas);
        descensoYDesintegracion << <dimGrid, dimBlock >> > (d_matriz, d_state, d_filas, d_columnas);
        comprobarSuelo << < dimGrid, dimBlock >> > (d_matriz, d_state, d_posicionNave, d_vidas, d_puntos, d_filas, d_columnas);
        crearAlienigenas << <dimGrid, dimBlock >> > (d_matriz, d_state, d_filas, d_columnas);
        
        // Copiamos a Host:
        cudaMemcpy(h_matriz, d_matriz, filas * columnas * sizeof(char), cudaMemcpyDeviceToHost);
        cudaMemcpy(&vidas, d_vidas, sizeof(short), cudaMemcpyDeviceToHost);
        cudaMemcpy(&puntos, d_puntos, sizeof(short), cudaMemcpyDeviceToHost);
        cudaMemcpy(&posicionNave, d_posicionNave, sizeof(short), cudaMemcpyDeviceToHost);
        
        pasos++;

        // Acelero la ejecución si estamos en modo auto y cada vez que los bichos avanzan "filas" filas
        if (modoAuto && pasos % filas == 0) {
            retardo = retardo - (retardoInicial*incrementoAceleracion/100);            
        }
                        
        imprimirEscenario(h_matriz);
        imprimirMarcador();

        if (vidas <= 0) {
            printf("Has perdido todas tus vidas :-(\n");
            break;
        }

    }

    // Liberar memoria
    cudaFree(d_vidas);
    cudaFree(d_puntos);
    cudaFree(d_posicionNave);
    cudaFree(d_matriz);
    cudaFree(d_state);
    cudaFree(d_filas);
    cudaFree(d_columnas);
    free(h_matriz);

    return 0;
}
