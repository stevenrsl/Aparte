#include <AudioToolbox/AudioToolbox.h>
#include <stdlib.h>
#include <unistd.h>

// Simulation au point où AVAudioFile écrit ses tampons, dans le seul producteur
// synthétique. -34 est dskFulErr (disque plein). Aucun disque n'est rempli.
static OSStatus ecrire(ExtAudioFileRef fichier, UInt32 trames, const AudioBufferList *tampons) {
    const char *marqueur = getenv("APARTE_PANNE_PLEIN");
    if (marqueur && access(marqueur, F_OK) == 0) { return -34; }
    return ExtAudioFileWrite(fichier, trames, tampons);
}
__attribute__((used, section("__DATA,__interpose")))
static const struct { const void *remplacement; const void *original; } substitution = {
    (const void *)ecrire, (const void *)ExtAudioFileWrite
};
