namespace WordReaderV2.Models;

public sealed class ReadingChapter
{
    public ReadingChapter(string title, IReadOnlyList<string> words)
    {
        Title = title;
        Words = words;
    }

    public string Title { get; }

    public IReadOnlyList<string> Words { get; }
}
