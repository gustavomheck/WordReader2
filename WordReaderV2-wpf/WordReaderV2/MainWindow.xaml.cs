using System.Windows;
using WordReaderV2.Services;
using WordReaderV2.ViewModels;

namespace WordReaderV2
{
    public partial class MainWindow : Window
    {
        public MainWindow()
        {
            InitializeComponent();
            DataContext = new MainWindowViewModel(new EpubBookService(), new FileDialogService());
        }
    }
}