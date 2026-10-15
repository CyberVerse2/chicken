import Testing
@testable import ChickenKit

struct TitleCasingTests {
    @Test func turnsAllCapsTitlesIntoTitleCase() {
        #expect("HOW CHINA ESCAPED THE POVERTY TRAP".readableTitle == "How China Escaped the Poverty Trap")
        #expect("THE LORD OF THE RINGS".readableTitle == "The Lord of the Rings")
        #expect("WHAT IT IS FOR".readableTitle == "What It Is For")
    }

    @Test func capitalizesAfterAColon() {
        #expect("SAPIENS: A BRIEF HISTORY OF HUMANKIND".readableTitle == "Sapiens: A Brief History of Humankind")
    }

    @Test func keepsNumeralsHyphensAndApostrophes() {
        #expect("WORLD WAR II".readableTitle == "World War II")
        #expect("1984 AND OTHER STORIES".readableTitle == "1984 and Other Stories")
        #expect("SELF-HELP FOR THE WEARY".readableTitle == "Self-Help for the Weary")
        #expect("DON'T PANIC".readableTitle == "Don't Panic")
        #expect("\"QUOTED\" TITLES".readableTitle == "\"Quoted\" Titles")
    }

    @Test func leavesMixedCaseAndAcronymsAlone() {
        #expect("The iPhone Book".readableTitle == "The iPhone Book")
        #expect("NASA".readableTitle == "NASA")
        #expect("1984".readableTitle == "1984")
        #expect("".readableTitle == "")
    }
}
