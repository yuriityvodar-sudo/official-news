// The list's two filters (#67, #68), as the app's (Yurii, 16 Oct): Where (All
// countries, a group of countries, or one country) and Topics (All topics, or
// one). Their names, for a filtered list's title.
import type { Topic } from "../../summarizer/schema";
import { type SiteLang, countryName, groupName, text, topicName } from "../texts";
import type { Place } from "../urls";

/** The full name of a place: All countries, the country's or the group's name. */
export const placeName = (lang: SiteLang, place: Place) =>
  place === null ? text(lang, "filterAllCountries") : "country" in place ? countryName(lang, place.country) : groupName(lang, place.group);

/** The topic's full name, or All topics. */
export const topicLabel = (lang: SiteLang, topic: Topic | null) => (topic ? topicName(lang, topic) : text(lang, "filterAllTopics"));
