using System.Net;
using System.IO;
using System.Text.RegularExpressions;
using WordReaderV2.Models;
using VersOne.Epub;

namespace WordReaderV2.Services;

public sealed class EpubBookService
{
    private static readonly Regex HtmlTagRegex = new("<[^>]+>", RegexOptions.Compiled);
    private static readonly Regex WordRegex = new(@"[\p{L}\p{M}\p{N}]+(?:['’\-][\p{L}\p{M}\p{N}]+)*", RegexOptions.Compiled);

    public async Task<IReadOnlyList<ReadingChapter>> LoadChaptersAsync(string filePath)
    {
        using EpubBookRef book = await EpubReader.OpenBookAsync(filePath);
        List<EpubLocalTextContentFileRef> readingOrder = await book.GetReadingOrderAsync();
        var chapters = new List<ReadingChapter>();

        foreach (EpubLocalTextContentFileRef contentFile in readingOrder)
        {
            string content = await contentFile.ReadContentAsTextAsync();
            IReadOnlyList<string> words = ExtractWords(content);

            if (words.Count > 0)
            {
                chapters.Add(new ReadingChapter(GetChapterTitle(contentFile.FilePath), words));
            }
        }

        return chapters;
    }

    private static IReadOnlyList<string> ExtractWords(string html)
    {
        string text = WebUtility.HtmlDecode(HtmlTagRegex.Replace(html, " "));
        return WordRegex.Matches(text).Select(match => match.Value).ToList();
    }

    private static string GetChapterTitle(string filePath)
    {
        string title = Path.GetFileNameWithoutExtension(filePath);
        return string.IsNullOrWhiteSpace(title) ? "Capítulo" : title;
    }
}
