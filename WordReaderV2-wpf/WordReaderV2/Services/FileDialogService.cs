using Microsoft.Win32;

namespace WordReaderV2.Services;

public sealed class FileDialogService : IFileDialogService
{
    public string? SelectEpubFile()
    {
        var dialog = new OpenFileDialog
        {
            Filter = "Arquivos EPUB (*.epub)|*.epub|Todos os arquivos (*.*)|*.*"
        };

        return dialog.ShowDialog() == true ? dialog.FileName : null;
    }
}
