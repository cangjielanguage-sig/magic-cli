package cli.core.tools.cj_utils

import std.convert.*
import std.fs.Path
import magic.dsl.jsonable
import magic.jsonable.*
import stdx.encoding.json.*
import std.deriving.Derive
import magic.log.LogUtils
import std.collection.{ArrayList, HashMap}
import std.regex.Regex

@Derive[ToString]
public struct Position {
    public Position(let file: Path, let line: Int32, let col: Int32) {}

    public static func tryParse(s: String): ?Position {
        let matchData = Regex("^==>\\s*(.+):(\\d+):(\\d+):$").find(s, group: true)
        match (matchData) {
            case Some(md) =>
                match ((Path(md.matchString(1)), Int32.tryParse(md.matchString(2)), Int32.tryParse(md.matchString(3)))) {
                    case (file, Some(line), Some(col)) => Position(file, line, col)
                    case _ => None
                }
            case None => None
        }
    }
}

@Derive[ToString]
@jsonable
protected enum DiagCategory {
    | Module
    | Tok
    | Parse
    | Sema
    | Unknown
}

@jsonable
protected struct FixSummary {
    public let category: DiagCategory
    public let title: String
    public let error_message: String
    public let cause_solution: String
    public let example: String
}

extend FixSummary {
    public static func fromMarkdown(s: String): ?FixSummary {
        // Parse the markdown format from CodeFixSummarizer
        let lines = s.split('\n')
        if (lines.size < 1) {
            return None
        }
        
        // Find title (starts with ###)
        var title = ""
        var error_message = ""
        var cause_solution = ""
        var example = ""
        var currentSection = ""
        
        for (line in lines) {
            let trimmed = line.trimAscii()
            
            if (trimmed.startsWith("### ")) {
                title = trimmed.replace("### ", "").trimAscii()
                currentSection = "title"
            }
            else if (trimmed == "#### Error Message") {
                currentSection = "error_message"
            }
            else if (trimmed == "#### Cause & Solution") {
                currentSection = "cause_solution"
            }
            else if (trimmed == "#### Example") {
                currentSection = "example"
            }
            else if (currentSection == "error_message") {
                error_message += line + '\n'
            }
            else if (currentSection == "cause_solution") {
                cause_solution += line + "\n"
            }
            else if (currentSection == "example") {
                example += line + "\n"
            }
        }
        
        // Clean up whitespace
        cause_solution = cause_solution.trimAscii()
        example = example.trimAscii()
        
        if (title.isEmpty() || error_message.isEmpty() || cause_solution.isEmpty() || example.isEmpty()) {
            return None
        }
        
        FixSummary(
            category: DiagCategory.Unknown, 
            title: title, 
            error_message: error_message,
            cause_solution: cause_solution, 
            example: example
        )
    }

    public func toMarkdown(): String {
        """
### ${title}

#### Error Message

${error_message}

#### Cause & Solution

${cause_solution}

#### Example

${example}
        """
    }
}

public func isSuccess(msg: String): Bool {
    msg.contains("cjpm build success")
}

protected struct CjpmBuildError {
    
    CjpmBuildError(
        /*
        diagnostic category, refer to --diagnostic-format=json
        */
        public let category: DiagCategory,
        /*
        error message, refer to --diagnostic-format=json
        */
        public let message: String,
        /*
        command line output of cjc when --diagnostic-format=default
        */
        public let fullError: String,
        /*
        in which file, which line and column

        this field is None in module error
        */
        public let location: ?Position,
        /*
        if this error is fixed by CangjieFixer and process by CodeFixSummarizer
        */
        public let fixSummary: ?FixSummary
        
    ) {}

    public static func tryParse(s: String): ?CjpmBuildError {
        // since we cannot get json diagnostic, the category is unknown
        let category = DiagCategory.Unknown
        let lines = s.split('\n')
        if (lines.size < 1) {
            return None
        }
        if (lines.size < 3) {
            return CjpmBuildError(DiagCategory.Module, lines[0], s, None, None)
        }
        let message = lines[0]
        let location = Position.tryParse(lines[1].trimAscii())
        CjpmBuildError(category, message, s, location, None)
    }
}